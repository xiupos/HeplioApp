import Foundation

/// One thing the reader did with a paper. The input to `ReadingProfile`,
/// and deliberately not a SwiftData model: the profile is arithmetic over
/// values, and keeping it that way is what lets the whole recommendation
/// layer be compiled and exercised from a scratch executable on a machine
/// that can't build SwiftUI.
///
/// The view layer maps `SavedPaper`/`ViewedPaper` to these through the
/// `PaperRecord.paper` snapshot it already has.
struct ReadingSignal {
    let paper: Paper
    /// Saved outranks merely opened — a bookmark is a deliberate act
    /// where a visit can be a mis-tap.
    let isSaved: Bool
    let date: Date
}

/// What the reader is interested in, as far as the app can tell.
///
/// **Computed, never stored.** This is a fold over the library and the
/// history — a few hundred rows, each carrying a snapshot capped at four
/// authors — so rebuilding it costs about as much as reading it back
/// would. That's not a happy accident, it's the design: the store is
/// destined for iCloud, and every piece of derived state kept there is a
/// migration and a merge conflict waiting to happen. Nothing here
/// survives the app being killed, and nothing here needs to.
struct ReadingProfile {
    /// The reader's papers, heaviest first. What a recommendation is
    /// built *from*.
    let seeds: [Seed]
    /// Weight per arXiv category, e.g. `"hep-th": 4.2`.
    let categories: [String: Double]
    let collaborations: [String: Double]
    /// Weight per INSPIRE subject keyword — the finest-grained thing this
    /// profile knows. An arXiv category says "hep-th"; a keyword says
    /// "field theory: conformal", and two hep-th readers can have nothing
    /// in common. Keyed on the lowercased form so a publisher's
    /// "AdS-CFT Correspondence" and INSPIRE's "AdS/CFT correspondence"
    /// at least stop being three different topics for spelling reasons.
    let keywords: [String: Double]
    /// The display spelling for each key above, since the key is folded.
    let keywordLabels: [String: String]
    /// Weight per `Paper.Author.id` — INSPIRE's disambiguated record id
    /// where there is one, so two physicists sharing a name stay apart.
    let authors: [String: Double]
    /// Weight per title word. Crude next to an embedding, but it's the
    /// difference between "some cosmology paper" and "a paper about
    /// primordial black holes", and it costs nothing.
    let terms: [String: Double]
    /// Every paper the reader has opened. Excluded from discovery — a
    /// recommendation you've already read isn't one. This is also what
    /// stands in for a stored list of what Home has featured before: the
    /// only thing that takes a paper out of circulation is reading it,
    /// which is a fact the store already keeps and already syncs.
    let readIDs: Set<Int>
    let savedIDs: Set<Int>
    /// The people behind `authors`, heaviest first. Kept as whole
    /// `Paper.Author` values rather than reconstructed from an id,
    /// because Home links to them and a link needs the affiliation and
    /// the record id, not just a weight.
    let rankedAuthors: [Paper.Author]

    struct Seed {
        let paper: Paper
        let weight: Double
    }

    var isEmpty: Bool { seeds.isEmpty }

    /// How fast an interest fades. A month is roughly the granularity at
    /// which someone's attention actually moves in this field — long
    /// enough that a paper read three weeks ago still counts, short
    /// enough that last year's project doesn't drown out this week's.
    private static let halfLifeDays: Double = 30

    private static let savedWeight: Double = 1.0
    private static let viewedWeight: Double = 0.6

    /// The most any one signal can contribute per facet, before decay.
    /// A collaboration paper credits four authors and two categories; the
    /// normalisation stops it counting four times as much as a two-author
    /// paper for the same act of reading.
    init(signals: [ReadingSignal], now: Date = .now) {
        var categories: [String: Double] = [:]
        var collaborations: [String: Double] = [:]
        var authors: [String: Double] = [:]
        var terms: [String: Double] = [:]
        var readIDs: Set<Int> = []
        var savedIDs: Set<Int> = []
        var seeds: [Seed] = []
        var authorRecords: [String: Paper.Author] = [:]
        var keywords: [String: Double] = [:]
        var keywordLabels: [String: String] = [:]

        // One entry per paper. The same paper can be both saved and
        // viewed, and counting it twice would let a single paper the
        // reader happened to bookmark outweigh two they didn't.
        var weightByID: [Int: Double] = [:]
        var paperByID: [Int: Paper] = [:]

        for signal in signals {
            let ageDays = max(0, now.timeIntervalSince(signal.date)) / 86_400
            let base = signal.isSaved ? Self.savedWeight : Self.viewedWeight
            let weight = base * exp(-ageDays / Self.halfLifeDays)

            if signal.isSaved { savedIDs.insert(signal.paper.id) } else { readIDs.insert(signal.paper.id) }

            // The heavier of the two wins rather than their sum.
            if let existing = weightByID[signal.paper.id], existing >= weight { continue }
            weightByID[signal.paper.id] = weight
            paperByID[signal.paper.id] = signal.paper
        }

        for (id, weight) in weightByID {
            guard let paper = paperByID[id] else { continue }
            seeds.append(Seed(paper: paper, weight: weight))

            Self.add(weight, of: paper.arxivCategories, to: &categories)
            Self.add(weight, of: paper.collaborations, to: &collaborations)
            Self.add(weight, of: paper.authors.map(\.id), to: &authors)
            Self.add(weight, of: paper.title.significantTerms, to: &terms)

            let topical = paper.topicalKeywords
            Self.add(weight, of: topical.map { $0.lowercased() }, to: &keywords)
            for keyword in topical {
                // First spelling seen wins, so the label stays stable
                // rather than flickering between two papers' casing.
                keywordLabels[keyword.lowercased()] = keywordLabels[keyword.lowercased()] ?? keyword
            }

            for author in paper.authors { authorRecords[author.id] = author }
        }

        self.seeds = seeds.sorted { $0.weight > $1.weight }
        self.rankedAuthors = authors
            .sorted { $0.value > $1.value }
            .compactMap { authorRecords[$0.key] }
        self.categories = categories
        self.collaborations = collaborations
        self.keywords = keywords
        self.keywordLabels = keywordLabels
        self.authors = authors
        self.terms = terms
        self.readIDs = readIDs
        self.savedIDs = savedIDs
    }

    /// The reader's subject keywords, heaviest first, in their display
    /// spelling. What Home's finest-grained topic shelves are made of.
    var rankedKeywords: [String] {
        keywords
            .sorted { $0.value > $1.value }
            .compactMap { keywordLabels[$0.key] }
    }

    /// A profile that knows nothing — a reader on their first launch.
    /// Home falls back to its impersonal shelves for this, and
    /// `Recommender` still runs: `score` just returns the quality prior,
    /// which is a perfectly sensible ordering to have nothing better than.
    static let empty = ReadingProfile(signals: [])

    /// Spreads one paper's weight across the things it's about, so a
    /// 2,932-author collaboration record doesn't hand every one of them a
    /// full vote.
    private static func add(_ weight: Double, of keys: [String], to bucket: inout [String: Double]) {
        guard !keys.isEmpty else { return }
        let share = weight / Double(keys.count)
        for key in keys {
            bucket[key, default: 0] += share
        }
    }

    // MARK: - Scoring

    /// How much this reader should want to see `candidate`, given what
    /// they've read.
    ///
    /// Ordering only. Whether a candidate is *eligible* — already read,
    /// already saved, one of the seeds — is `Recommender`'s business, not
    /// this function's: zero is a real score (an uncited preprint under
    /// an empty profile earns exactly it), so it can't also be a sentinel
    /// for "skip this one" without one meaning eating the other.
    ///
    /// The overlap terms answer different questions — who wrote it, what
    /// field it's in, what it's about — and the citation prior is
    /// deliberately weak: it breaks ties between papers the reader has
    /// equal claim to, and is not allowed to turn every shelf into
    /// Landmarks. It's `log1p` for the obvious reason that the difference
    /// between 0 and 10 citations means something and the difference
    /// between 900 and 910 does not.
    ///
    /// **Keywords are weighted above everything but the author**, and
    /// above the arXiv category in particular, because they're the term
    /// that actually discriminates: a category shared with a candidate
    /// says only that both are, say, hep-th, which a third of the
    /// literature is. A shared "field theory: conformal" is a real claim
    /// about the subject. The category term is kept rather than replaced
    /// — it's the only signal that survives for a paper too recent to
    /// have been indexed yet.
    func score(_ candidate: Paper) -> Double {
        let authorScore = Self.overlap(candidate.authors.map(\.id), with: authors)
        let categoryScore = Self.overlap(candidate.arxivCategories, with: categories)
        let collaborationScore = Self.overlap(candidate.collaborations, with: collaborations)
        let termScore = Self.overlap(candidate.title.significantTerms, with: terms)
        let keywordScore = Self.overlap(
            candidate.topicalKeywords.map { $0.lowercased() },
            with: keywords
        )

        return 3.0 * authorScore
            + 2.5 * keywordScore
            + 1.5 * categoryScore
            + 1.5 * collaborationScore
            + 2.0 * termScore
            + 0.1 * log1p(Double(candidate.citationCount))
    }

    /// Averaged over the candidate's own keys rather than summed, so a
    /// paper doesn't score highly just for listing a lot of categories.
    private static func overlap(_ keys: [String], with bucket: [String: Double]) -> Double {
        guard !keys.isEmpty, !bucket.isEmpty else { return 0 }
        let total = keys.reduce(0.0) { $0 + (bucket[$1] ?? 0) }
        return total / Double(keys.count)
    }
}

extension String {
    /// Title words worth counting as a topic.
    ///
    /// Runs through `resolvingInlineMarkup` first so a `<sup>` doesn't
    /// become vocabulary, then drops anything with a backslash or a
    /// dollar in it — LaTeX fragments like `\mathcal{N}=4` tokenize into
    /// noise, and the words around them carry the topic anyway. Short
    /// words and a small stopword list go too.
    ///
    /// The stopword list is deliberately tiny and physics-blind. Words
    /// that would look like filler in ordinary English — "measurement",
    /// "search", "effective", "model" — are exactly the words that
    /// distinguish an experimental paper from a theory one here, so they
    /// stay.
    var significantTerms: [String] {
        resolvingInlineMarkup
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
            .filter { term in
                term.count > 3 && !Self.stopwords.contains(term)
            }
    }

    private static let stopwords: Set<String> = [
        "with", "from", "that", "this", "these", "those", "their", "there",
        "using", "used", "into", "over", "under", "between", "within",
        "have", "been", "were", "which", "when", "where", "what",
        "about", "after", "before", "through", "toward", "towards",
        "some", "more", "most", "other", "than", "then", "also",
        "case", "cases", "note", "notes", "paper", "papers"
    ]
}
