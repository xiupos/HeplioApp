import Foundation

/// One row of the Home tab, and everything the app needs to know about it
/// apart from how to draw it.
///
/// The same trick `BrowseTopic` plays for Explore: because every shelf
/// reduces to a description plus a way of getting papers, adding one is a
/// case here rather than a new view. `Foundation`-only for the same
/// reason as the rest of `Recommendation/` — the stream that orders these
/// is the interesting part, and it can be checked on a machine that can't
/// build SwiftUI.
enum HomeShelf: Hashable, Identifiable {
    /// The whole reading profile, ranked. The one shelf that is always
    /// first, because it's the one the tab is for.
    case forYou
    /// One paper the reader has read, and its siblings.
    case becauseYouRead(Paper)
    /// More by someone they read a lot of.
    case author(Paper.Author)
    /// A corner of the literature they keep returning to. `reason`
    /// carries why it's on *Home* rather than Explore.
    case topic(BrowseTopic, reason: String?)
    /// Opened once and never bookmarked. A grid of tiles, no requests.
    case readAgain(ArxivCategory?)
    /// Bookmarked and possibly forgotten. Likewise local.
    case fromLibrary(ArxivCategory?)
    /// Tiles rather than papers — somewhere to go, not something to read.
    case topicsForYou([BrowseTopic])
    case authorsToFollow([Paper.Author])
    /// The two impersonal shelves. They exist for variety and for the
    /// cold start, and they are deliberately never part of the spine:
    /// Home is *you*, and a Home led by what everyone else is reading is
    /// just Explore with a different title.
    case trending
    case newAtRandom

    var id: Self { self }

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .becauseYouRead: return "Because You Read"
        case .author: return "More By"
        case .topic(let topic, _): return topic.title
        case .readAgain: return "Read Again"
        case .fromLibrary: return "From Your Library"
        case .topicsForYou: return "Topics for You"
        case .authorsToFollow: return "Authors to Follow"
        case .trending: return BrowseTopic.trending.title
        case .newAtRandom: return "New This Fortnight"
        }
    }

    /// The second line of the header. Where a shelf says *why* it is on
    /// this screen — which is the whole difference between Home's
    /// "Theory · Because you keep reading it" and Explore's "Theory".
    var subtitle: String? {
        switch self {
        case .becauseYouRead(let paper): return paper.title.resolvingInlineMarkup
        case .author(let author): return author.fullName
        case .topic(_, let reason): return reason
        case .readAgain(let category): return category?.displayName ?? "Opened but not saved"
        case .fromLibrary(let category): return category?.displayName ?? "Saved for later"
        case .forYou: return "From what you've been reading"
        case .topicsForYou, .authorsToFollow: return nil
        case .trending: return "Recent work already being cited"
        case .newAtRandom: return "A random look at what's arrived"
        }
    }

    var icon: String? {
        switch self {
        case .forYou: return "sparkles"
        case .becauseYouRead: return "text.book.closed"
        case .author: return "person"
        case .topic: return "square.grid.2x2"
        case .readAgain: return "arrow.counterclockwise"
        case .fromLibrary: return "bookmark"
        case .topicsForYou: return "square.grid.2x2"
        case .authorsToFollow: return "person.3"
        case .trending: return "flame"
        case .newAtRandom: return "newspaper"
        }
    }

    /// A stable string to salt this shelf's `DailySeed` with, so two
    /// shelves drawing from the same list on the same day don't draw the
    /// same order.
    var seedSalt: String {
        switch self {
        case .forYou: return "forYou"
        case .becauseYouRead(let paper): return "because-\(paper.id)"
        case .author(let author): return "author-\(author.id)"
        case .topic(let topic, _): return "topic-\(topic.query)"
        case .readAgain(let category): return "readAgain-\(category?.rawValue ?? "all")"
        case .fromLibrary(let category): return "library-\(category?.rawValue ?? "all")"
        case .topicsForYou: return "topicsForYou"
        case .authorsToFollow: return "authorsToFollow"
        case .trending: return "trending"
        case .newAtRandom: return "newAtRandom"
        }
    }

    /// Whether this shelf exists *because of who the reader is*, as
    /// opposed to being something anyone would see. Drives the tinted
    /// panel — see `shelfPanel(tinted:)`.
    ///
    /// The line is drawn at "would this shelf be here for someone else
    /// too". A recommendation and an author the reader keeps returning to
    /// wouldn't be; a topic, their own library and Trending all would, in
    /// the sense that they're a place or a list rather than an inference.
    var isPersonal: Bool {
        switch self {
        case .forYou, .becauseYouRead, .author: return true
        case .topic, .readAgain, .fromLibrary, .topicsForYou,
             .authorsToFollow, .trending, .newAtRandom: return false
        }
    }

    /// Whether filling this shelf costs a request. The stream uses it to
    /// keep any three consecutive shelves from all being network ones —
    /// see `HomeShelfStream`.
    var needsNetwork: Bool {
        switch self {
        case .forYou, .becauseYouRead, .author, .topic, .trending, .newAtRandom:
            return true
        case .readAgain, .fromLibrary, .topicsForYou, .authorsToFollow:
            return false
        }
    }

    /// Which papers belong on this shelf, for the shelves that are a plain
    /// INSPIRE query. The rest are answered by `HomeShelfView` from the
    /// reader's own store, or aren't papers at all.
    var query: (text: String, sort: InspireHEPClient.SortOrder)? {
        switch self {
        case .topic(let topic, _): return (topic.query, topic.defaultSort)
        case .trending: return (BrowseTopic.trending.query, BrowseTopic.trending.defaultSort)
        // The New tab's own query string, character for character, so
        // this is a `ResponseCache` hit for anyone who has opened that tab
        // today rather than a second request for the same thing.
        case .newAtRandom: return (NewFeedSelection.all.query, .mostRecent)
        case .author(let author): return (author.papersQuery, .mostRecent)
        case .forYou, .becauseYouRead, .readAgain, .fromLibrary, .topicsForYou, .authorsToFollow:
            return nil
        }
    }
}

/// The order Home puts its shelves in today, and how far it goes.
///
/// **A pure function of the profile and the calendar day.** Nothing is
/// stored, so there is no algorithm state to sync, migrate or reconcile
/// when this store reaches iCloud — and two devices asked on the same day
/// produce the same screen without having exchanged anything. See
/// `DailySeed`.
///
/// The whole list is built at once rather than generated lazily. It runs
/// to about a hundred entries — bounded by the size of the library, the
/// history and the `BrowseTopic` catalog — and each entry is a few words,
/// so paging is a `prefix`, and knowing where the end is comes free.
struct HomeShelfStream {
    /// Today's shelves, in order, longest to shortest patience.
    let shelves: [HomeShelf]

    /// How many shelves a scroll reveals at a time. Three keeps the
    /// request burst small: the interleave below guarantees at most one
    /// network shelf per pair, so a page costs one or two requests.
    static let pageSize = 3

    /// - Parameters:
    ///   - profile: What the reader has read. An empty one falls back to
    ///     the impersonal families, which is the cold start.
    ///   - preferredCategory: The New tab's chip. It's the one interest a
    ///     reader states out loud rather than one this app infers, so on
    ///     a first launch — when there is nothing else — it decides what
    ///     Home opens on.
    init(
        profile: ReadingProfile,
        preferredCategory: ArxivCategory? = nil,
        day: String = Date.now.inspireDay
    ) {
        let dice = DailySeed(day: day, salt: "shelves")

        // MARK: The spine
        //
        // Always these, always in this order. A tab whose first row moves
        // around is a tab you have to re-read every morning; what changes
        // daily is *which paper* the second one is about, which is enough
        // to keep the screen from reading as yesterday's.
        var spine: [HomeShelf] = []
        if !profile.isEmpty {
            spine.append(.forYou)
            if let featured = dice.pick(Array(profile.seeds.prefix(Self.featuredSeedPool))) {
                spine.append(.becauseYouRead(featured.paper))
            }
        }

        // MARK: The families
        //
        // Each is an unbounded-ish ranked list, day-shuffled, drained in
        // turn. The interleave below is what keeps a page from being all
        // network or all local.
        var network = Self.networkFamilies(
            profile: profile,
            preferredCategory: preferredCategory,
            dice: dice,
            excluding: Set(spine)
        )
        var local = Self.localFamilies(profile: profile, dice: dice)

        var ordered = spine
        // Alternating, **local first**, so that no three shelves in a row
        // all cost a request.
        //
        // Local first because the spine is itself two network shelves: a
        // rotation that opened with a third would put the worst burst of
        // the whole screen at the top, where every reader meets it.
        //
        // One local per network rather than two, because local shelves
        // are the scarcer resource — they're bounded by how much the
        // reader has actually read — and spending them one at a time
        // makes the protected stretch twice as long.
        //
        // The guarantee holds only while both queues have entries. Past
        // the point where the local ones run out the tail is network all
        // the way down, and there is nothing free left to pad it with.
        // That's deep enough into a scroll to be a non-issue:
        // `InspireHEPClient` throttles at 15 requests / 5s by blocking,
        // not by failing, so a fast scroll through the tail is slow
        // rather than broken.
        while !network.isEmpty || !local.isEmpty {
            if !local.isEmpty { ordered.append(local.removeFirst()) }
            if !network.isEmpty { ordered.append(network.removeFirst()) }
        }

        self.shelves = ordered
    }

    /// How deep into the reading profile the day's featured paper is
    /// drawn from. Wide enough that a month of mornings doesn't repeat,
    /// narrow enough that it's still something the reader cared about.
    private static let featuredSeedPool = 30

    private static let maxBecauseYouRead = 25
    private static let maxAuthorShelves = 15
    /// Tiles in one grid. Two rows on an iPhone, one on an iPad.
    private static let tilesPerGrid = 8
    /// How far down the reader's keyword ranking to go. A well-read
    /// profile turns up hundreds of them (1,916 distinct across a sample
    /// of 400 papers), and the tail is one-off terms from a single paper
    /// — which would be a shelf built on a coincidence.
    private static let maxKeywordTopics = 40

    // MARK: - Families

    private static func networkFamilies(
        profile: ReadingProfile,
        preferredCategory: ArxivCategory?,
        dice: DailySeed,
        excluding: Set<HomeShelf>
    ) -> [HomeShelf] {
        var queues: [[HomeShelf]] = []

        let seeds = dice.shuffled(Array(profile.seeds.prefix(maxBecauseYouRead)))
        queues.append(seeds.map { .becauseYouRead($0.paper) })

        let authors = dice.shuffled(Array(profile.rankedAuthors.prefix(maxAuthorShelves)))
        queues.append(authors.map { .author($0) })

        queues.append(topicShelves(profile: profile, preferredCategory: preferredCategory, dice: dice))

        // Variety, not the main course — one of each, dropped in among
        // the personal shelves rather than leading them.
        queues.append([.trending, .newAtRandom])

        return roundRobin(queues).filter { !excluding.contains($0) }
    }

    private static func localFamilies(profile: ReadingProfile, dice: DailySeed) -> [HomeShelf] {
        // A reader on their first launch has no library to slice and no
        // authors to rank, so the only local shelf that means anything is
        // a look at the catalog. Everything else on their Home comes from
        // the network families — Explore's material, until they've read
        // enough for this tab to be about them.
        guard !profile.isEmpty else {
            return [.topicsForYou(Array(dice.shuffled(BrowseTopic.categories).prefix(tilesPerGrid)))]
        }

        // Sliced by category rather than repeated verbatim: "Read Again"
        // four times over is a bug report, "Read Again · Cosmology" is a
        // shelf. It's also what makes these unbounded enough to scroll
        // through, which is the point of slicing them at all.
        let categories = dice.shuffled(
            profile.categories
                .sorted { $0.value > $1.value }
                .compactMap { ArxivCategory(rawValue: $0.key) }
        )

        // The two grids appear once each, near the top of the local
        // rotation: they're signposts rather than reading, and a second
        // helping of signposts is a menu.
        var signposts: [HomeShelf] = []
        let topics = Array(shuffledInterests(of: profile, dice: dice).prefix(Self.tilesPerGrid))
        if !topics.isEmpty { signposts.append(.topicsForYou(topics)) }
        let authors = Array(profile.rankedAuthors.prefix(Self.tilesPerGrid))
        if !authors.isEmpty { signposts.append(.authorsToFollow(authors)) }

        var queues: [[HomeShelf]] = [signposts]
        queues.append([.readAgain(nil)] + categories.map { .readAgain($0) })
        queues.append([.fromLibrary(nil)] + categories.map { .fromLibrary($0) })
        return roundRobin(queues)
    }

    /// The corners of the literature the reader keeps landing in, heaviest
    /// first, expressed as the same `BrowseTopic` values Explore's shelves
    /// and `BrowseListView` already speak.
    ///
    /// **Keywords lead, categories come last.** An arXiv category is far
    /// too coarse to be a "topic you're interested in" — two hep-th
    /// readers can be in different worlds, and a shelf called "Theory"
    /// tells someone nothing they didn't know. INSPIRE's own subject
    /// keywords are the right grain ("field theory: conformal",
    /// "neutrino: oscillation"), and are the same vocabulary its own site
    /// browses by.
    ///
    /// Categories stay on the end rather than being dropped, because
    /// keyword coverage is not universal: INSPIRE's curated indexing runs
    /// a couple of years behind (measured: 100% of hep-th papers up to
    /// ~2022, 0% from 2024), so a reader whose library is all brand-new
    /// preprints has only their free-form author keywords and, failing
    /// that, the category.
    ///
    /// Returned as tiers rather than one flat list, because the caller
    /// shuffles for daily variety and a shuffle across the whole thing
    /// would throw this ordering straight back away — which it silently
    /// did, until a test asked whether keywords really came first.
    /// Shuffling happens *within* each tier instead.
    private static func interestTiers(of profile: ReadingProfile) -> [[BrowseTopic]] {
        let keywords = profile.rankedKeywords
            .prefix(maxKeywordTopics)
            .map { BrowseTopic.keyword($0) }
        let collaborations: [BrowseTopic] = profile.collaborations
            .sorted { $0.value > $1.value }
            .map { BrowseTopic.collaboration($0.key) }
        let categories: [BrowseTopic] = profile.categories
            .sorted { $0.value > $1.value }
            .compactMap { ArxivCategory(rawValue: $0.key).map(BrowseTopic.category) }
        return [Array(keywords), collaborations, categories]
    }

    /// The reader's interests in one list, varied by the day but with the
    /// tiers still in order: which keyword leads changes each morning,
    /// keywords still come before categories.
    ///
    /// **This is the only correct way to shuffle them, and both callers
    /// need it.** Flattening first and shuffling the result looks
    /// identical and quietly throws the tiering away — a mistake made
    /// once in each of the two places before a test caught the first.
    private static func shuffledInterests(
        of profile: ReadingProfile,
        dice: DailySeed
    ) -> [BrowseTopic] {
        interestTiers(of: profile).flatMap { dice.shuffled($0) }
    }

    /// Topics the reader has shown an interest in first, then the rest of
    /// the catalog — so Home starts with their corner of the field and
    /// widens out rather than the other way round.
    private static func topicShelves(
        profile: ReadingProfile,
        preferredCategory: ArxivCategory?,
        dice: DailySeed
    ) -> [HomeShelf] {
        var familiar = shuffledInterests(of: profile, dice: dice)
        // The stated interest outranks every inferred one, and on a first
        // launch it's the only thing here at all.
        if let preferredCategory {
            let stated = BrowseTopic.category(preferredCategory)
            familiar.removeAll { $0 == stated }
            familiar.insert(stated, at: 0)
        }

        let rest = dice.shuffled(
            (BrowseTopic.categories + BrowseTopic.collaborations + BrowseTopic.collections)
                .filter { !familiar.contains($0) }
        )

        return familiar.map { .topic($0, reason: "Based on what you read") }
            + rest.map { .topic($0, reason: $0.subtitle) }
    }

    /// Drains several ranked lists one entry at a time, so no single
    /// family owns the top of the screen.
    private static func roundRobin(_ queues: [[HomeShelf]]) -> [HomeShelf] {
        var result: [HomeShelf] = []
        var seen: Set<HomeShelf> = []
        let deepest = queues.map(\.count).max() ?? 0
        for index in 0..<deepest {
            for queue in queues where index < queue.count {
                let shelf = queue[index]
                if seen.insert(shelf).inserted { result.append(shelf) }
            }
        }
        return result
    }
}
