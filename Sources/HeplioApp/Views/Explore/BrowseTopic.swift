import Foundation

/// One entry on the Explore shelf, and the navigation value that opens
/// it. Everything here reduces to an INSPIRE query string, which is what
/// lets a category, an experiment and a document type all be the same
/// screen (`BrowseListView`) instead of three.
///
/// The shelves themselves are hard-coded below. That isn't a shortcut:
/// INSPIRE's API returns no facets, so there is no list to fetch.
enum BrowseTopic: Hashable, Codable {
    case trending
    case category(ArxivCategory)
    case collaboration(String)
    /// One of INSPIRE's own subject keywords — "field theory: conformal",
    /// "neutrino: oscillation". Much finer than a category, which is the
    /// point: two papers in hep-th can be in different worlds, and the
    /// category can't tell them apart. Not on Explore's shelves (there's
    /// no fixed list to hard-code — the vocabulary runs to thousands of
    /// terms), only reached from a reader's own profile on Home.
    case keyword(String)
    case reviews
    case lectureNotes
    case landmarks

    var title: String {
        switch self {
        case .trending: return "Trending"
        case .category(let category): return category.displayName
        case .collaboration(let name): return name
        // INSPIRE writes its vocabulary lowercase ("field theory:
        // conformal"); only the first letter is raised, because
        // `.capitalized` would wreck the acronyms and particle names all
        // through it ("AdS/CFT", "p p", "CP").
        case .keyword(let keyword): return keyword.prefix(1).uppercased() + keyword.dropFirst()
        case .reviews: return "Review Articles"
        case .lectureNotes: return "Lecture Notes"
        case .landmarks: return "Landmarks"
        }
    }

    /// The second line on a tile. For a category it's the arXiv
    /// identifier — this audience says "hep-ph" more often than
    /// "Phenomenology", so the tile shows both rather than picking one.
    /// For an experiment it's where the data comes from, which turns a
    /// column of names into something closer to a map.
    var subtitle: String? {
        switch self {
        case .category(let category): return category.rawValue
        case .collaboration(let name): return Self.facilities[name]
        case .keyword: return nil
        case .reviews: return "Surveys of a field"
        case .lectureNotes: return "Written to teach"
        case .landmarks: return "The most cited work"
        case .trending: return nil
        }
    }

    var query: String {
        switch self {
        case .trending:
            // Recent papers that are *already* being cited. No inference
            // and no editorial judgement — the citations are real, which
            // is exactly why this belongs on Explore and a "top story"
            // pick doesn't belong on New.
            return "de > \(Self.trendingWindowStart) and topcite 5+"
        case .category(let category):
            return category.browseQuery
        case .collaboration(let name):
            // Quoted: names with spaces or hyphens ("Muon g-2",
            // "LIGO Scientific") don't match reliably bare.
            return "collaboration:\"\(name)\""
        case .keyword(let keyword):
            // `k` is INSPIRE's shorthand for `keywords.value`; verified
            // live that all three spellings return the same count.
            // Quoted for the same reason as a collaboration name — these
            // contain spaces, colons and slashes ("field theory:
            // conformal", "AdS/CFT correspondence").
            return "k \"\(keyword)\""
        case .reviews:
            // INSPIRE's type codes, not a `document_type` field —
            // `doc_type:review` returns zero hits.
            return "tc r"
        case .lectureNotes:
            return "tc l"
        case .landmarks:
            return "topcite 1000+"
        }
    }

    /// Which sort a topic opens on. Most shelves are "what's new in this
    /// corner"; the two that are explicitly about standing start ranked
    /// by it, since a Landmarks list sorted by date would be nonsense.
    var defaultSort: InspireHEPClient.SortOrder {
        switch self {
        case .trending, .landmarks: return .mostCited
        default: return .mostRecent
        }
    }

    var itemNoun: String {
        switch self {
        case .reviews: return "reviews"
        case .lectureNotes: return "lecture notes"
        default: return "papers"
        }
    }

    // MARK: - The shelves

    static let categories = ArxivCategory.allCases.map(BrowseTopic.category)

    /// The experiments a HEP reader would recognize on sight, roughly by
    /// how much of the literature they account for. Every name was
    /// checked against `collaboration:"…"` — INSPIRE's spelling is
    /// authoritative here and not always the obvious one ("Belle-II",
    /// "LIGO Scientific").
    static let collaborations: [BrowseTopic] = [
        "ATLAS", "CMS", "LHCb", "ALICE",
        "Belle", "Belle-II", "BaBar", "CDF",
        "IceCube", "Pierre Auger", "LIGO Scientific", "Fermi-LAT",
        "DUNE", "T2K", "XENON", "Muon g-2"
    ].map(BrowseTopic.collaboration)

    static let collections: [BrowseTopic] = [.reviews, .lectureNotes, .landmarks]

    /// Where each experiment's data comes from. Not in the API — this is
    /// the one piece of hand-written curation on the screen, and it earns
    /// its place: sixteen bare acronyms are a dropdown, sixteen acronyms
    /// with places attached are a field to wander around in.
    private static let facilities: [String: String] = [
        "ATLAS": "CERN, LHC",
        "CMS": "CERN, LHC",
        "LHCb": "CERN, LHC",
        "ALICE": "CERN, LHC",
        "Belle": "KEK, KEKB",
        "Belle-II": "KEK, SuperKEKB",
        "BaBar": "SLAC, PEP-II",
        "CDF": "Fermilab, Tevatron",
        "IceCube": "South Pole",
        "Pierre Auger": "Malargüe, Argentina",
        "LIGO Scientific": "Hanford and Livingston",
        "Fermi-LAT": "Space telescope",
        "DUNE": "Fermilab to SURF",
        "T2K": "J-PARC to Super-Kamiokande",
        "XENON": "Gran Sasso",
        "Muon g-2": "Fermilab"
    ]

    /// How far back "recent, and already being cited" reaches. Long
    /// enough that a paper has had time to collect its first citations,
    /// short enough that the shelf isn't just Landmarks again.
    private static let trendingWindowDays = 60

    /// The window's start, as INSPIRE's `yyyy-MM-dd`. Recomputed per call
    /// — see `Date.daysAgo(_:)` for why that's the point rather than an
    /// oversight.
    private static var trendingWindowStart: String {
        Date.daysAgo(trendingWindowDays).inspireDay
    }
}
