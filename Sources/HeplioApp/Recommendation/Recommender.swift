import Foundation

/// The ranking function, in one shape: **given a set of papers, return
/// ranked related ones.**
///
/// Written general from the start on purpose. The detail screen's
/// "Related" carousel passes one paper; Home passes a whole library. A
/// Related-only shortcut would have had to be thrown away the moment Home
/// needed the same thing over a set.
///
/// There is no local corpus to rank against — the app knows about a few
/// hundred papers and INSPIRE knows about a few million — so candidates
/// come from the API and the ranking happens here. What makes that cheap
/// is that **INSPIRE performs the join**: a whole reading profile is one
/// `or` of `refersto` clauses, one request, not one request per seed.
/// Verified live — 12 seeds, 285 hits, a 433-character URL.
enum Recommender {
    /// Which citation edge to follow out of the seeds. Both are one
    /// query; they answer different questions.
    enum Edge {
        /// Papers that **cite** the seeds — descendants. "What's new that
        /// builds on what you read." Right for a set of papers, and what
        /// Home's "For You" runs on.
        case citingWork

        /// Papers that cite the seeds' **references** — siblings rather
        /// than descendants: other work built on the same foundations.
        ///
        /// This is what a single paper's "Related" needs, and it has to be
        /// a different edge from the one above, because for one paper
        /// `refersto:recid:X` is *already* the Cited By carousel sitting
        /// next to it. Related has to mean something Cited By doesn't.
        case sharedFoundations
    }

    /// How many seeds go into one query. Twelve keeps the URL around 430
    /// characters and the answer specific; past that the union widens
    /// until it stops describing anyone in particular.
    private static let maxSeedsPerQuery = 12

    /// How far back `.citingWork` looks. Long enough that a modest
    /// reading profile still turns up something, short enough that "for
    /// you" doesn't mean "the last decade".
    private static let citingWindowDays = 180

    /// How many candidates to ask INSPIRE for before ranking locally.
    /// Four pages' worth in one request: the re-rank needs room to
    /// actually change the order, and a `size=40` search costs exactly as
    /// much as a `size=10` one.
    private static let candidatePoolSize = 40

    /// At most this many papers by the same first author in one result,
    /// so a prolific group can't take the shelf over.
    private static let maxPerAuthor = 2

    /// - Parameters:
    ///   - seeds: The papers to find relatives of.
    ///   - edge: Which way to walk the citation graph — see `Edge`.
    ///   - profile: Whose taste to rank by, and what to leave out. Pass
    ///     `.empty` to rank by nothing but citation count.
    ///   - dailySeed: When set, the top of the ranking is *sampled*
    ///     rather than taken, so a shelf differs from day to day. Nil for
    ///     a "See All" list, which wants the ranking itself, in order.
    ///   - page: For paging a full list. Ignored by the sampled path,
    ///     which only ever shows one shelf's worth.
    static func related(
        to seeds: [Paper],
        via edge: Edge,
        profile: ReadingProfile,
        dailySeed: DailySeed? = nil,
        limit: Int = PaperService.pageSize,
        page: Int = 1,
        refresh: Bool = false
    ) async throws -> [Paper] {
        guard let query = query(for: seeds, via: edge, dailySeed: dailySeed) else { return [] }

        var candidates = try await PaperService.shared.search(
            query: query,
            sort: .mostCited,
            page: page,
            size: candidatePoolSize,
            refresh: refresh
        )

        // A sparse profile — two papers, both obscure — can come back
        // empty from a windowed query while having perfectly good
        // relatives outside the window. One retry, only in that case.
        if candidates.isEmpty, page == 1, case .citingWork = edge,
           let unwindowed = self.query(for: seeds, via: .citingWork, dailySeed: dailySeed, windowed: false) {
            candidates = try await PaperService.shared.search(
                query: unwindowed,
                sort: .mostCited,
                page: page,
                size: candidatePoolSize,
                refresh: refresh
            )
        }

        // **Rank against the seeds as well as the reader.** Without this
        // the only signal on a screen with no reading history is the
        // citation prior, and a citation prior on its own doesn't return
        // related papers — it returns famous ones. Asked for work related
        // to Maldacena's AdS/CFT paper it answered with the Review of
        // Particle Physics, which is cited by everything and about
        // nothing. The seeds are the topic; that's what the candidates
        // have to look like.
        let subject = ReadingProfile(signals: seeds.map {
            ReadingSignal(paper: $0, isSaved: true, date: .now)
        })

        // Exclusion is stated here rather than inferred from the score.
        // A score of zero is a legitimate answer — an uncited preprint
        // under an empty profile scores exactly that — so reading "0" as
        // "already seen" would have quietly dropped every new paper on a
        // first launch, which is the one reader who can least afford it.
        let seedIDs = Set(seeds.map(\.id))
        let ranked = candidates
            .filter { candidate in
                candidate.hasInspireRecord
                    && !seedIDs.contains(candidate.id)
                    && !profile.readIDs.contains(candidate.id)
                    && !profile.savedIDs.contains(candidate.id)
            }
            .map { (paper: $0, score: subject.score($0) + profile.score($0)) }
            .sorted { $0.score > $1.score }

        let diverse = capPerAuthor(ranked)

        guard let dailySeed else { return Array(diverse.prefix(limit)).map(\.paper) }
        // Sampled from the whole ranked pool rather than sliced off the
        // top: taking the best `limit` would be stable within a day and
        // identical every day, which is the thing this is here to avoid.
        return dailySeed.sample(diverse, count: limit) { max($0.score, .leastNonzeroMagnitude) }
            .map(\.paper)
    }

    /// Papers to feature from a set the app already has in hand — no
    /// network at all. What the "Read Again" and "From Your Library"
    /// shelves run on, and the reason they cost nothing.
    static func featured(from papers: [Paper], dailySeed: DailySeed, limit: Int) -> [Paper] {
        dailySeed.sample(papers, count: limit) { _ in 1 }
    }

    // MARK: - Query construction

    /// Split out so a scratch executable can assert the string without
    /// making a request, and so both call sites above build it the same
    /// way.
    static func query(
        for seeds: [Paper],
        via edge: Edge,
        dailySeed: DailySeed?,
        windowed: Bool = true
    ) -> String? {
        let anchors: [Int]
        switch edge {
        case .citingWork:
            anchors = Array(seeds.filter(\.hasInspireRecord).map(\.id).prefix(maxSeedsPerQuery))
        case .sharedFoundations:
            anchors = foundations(of: seeds, dailySeed: dailySeed)
        }
        guard !anchors.isEmpty else { return nil }

        // Parenthesised for the same reason `NewFeedSelection` parenthesises
        // its category union: `A or B and C` binds the wrong way, and the
        // result looks plausible rather than wrong.
        let union = anchors.map { "refersto:recid:\($0)" }.joined(separator: " or ")
        var clauses = ["(\(union))"]

        switch edge {
        case .citingWork:
            // Nothing cites itself, so the seeds can't come back here.
            if windowed {
                clauses.append("de > \(Date.daysAgo(citingWindowDays).inspireDay)")
            }
        case .sharedFoundations:
            // A paper does cite its own references, so without this the
            // first thing "Related" shows is the paper you're looking at.
            clauses.append(contentsOf: seeds.filter(\.hasInspireRecord).map { "not recid:\($0.id)" })
        }

        return clauses.joined(separator: " and ")
    }

    /// The references to walk out from, for `.sharedFoundations`.
    ///
    /// A bibliography is a mix of the papers a work is actually built on
    /// and the ones it merely tips its hat to — a software citation, a
    /// review, the textbook. Ranking by how much a reference's title
    /// shares with the source's picks out the former, which is what makes
    /// the resulting siblings on-topic rather than "everything that ever
    /// cited FeynCalc".
    ///
    /// Sampled from that shortlist rather than taken from the top so this
    /// shelf, too, differs from one day to the next.
    private static func foundations(of seeds: [Paper], dailySeed: DailySeed?) -> [Int] {
        var scored: [(id: Int, score: Double)] = []
        for seed in seeds {
            let subject = ReadingProfile(signals: [ReadingSignal(paper: seed, isSaved: true, date: .now)])
            for reference in seed.references where reference.hasInspireRecord {
                scored.append((reference.id, subject.score(reference)))
            }
        }
        guard !scored.isEmpty else { return [] }

        let shortlist = Array(scored.sorted { $0.score > $1.score }.prefix(maxSeedsPerQuery * 2))
        guard let dailySeed else { return Array(shortlist.prefix(maxSeedsPerQuery)).map(\.id) }
        return dailySeed.sample(shortlist, count: maxSeedsPerQuery) { max($0.score, .leastNonzeroMagnitude) }
            .map(\.id)
    }

    // MARK: - Diversity

    /// Keeps the order but drops a paper once its first author already has
    /// `maxPerAuthor` in the list. First author rather than all of them
    /// because that's the one a row shows, so it's the repetition a reader
    /// would actually notice.
    private static func capPerAuthor(
        _ ranked: [(paper: Paper, score: Double)]
    ) -> [(paper: Paper, score: Double)] {
        var counts: [String: Int] = [:]
        return ranked.filter { entry in
            guard let key = entry.paper.authors.first?.id ?? entry.paper.collaborations.first else { return true }
            counts[key, default: 0] += 1
            return counts[key]! <= maxPerAuthor
        }
    }
}
