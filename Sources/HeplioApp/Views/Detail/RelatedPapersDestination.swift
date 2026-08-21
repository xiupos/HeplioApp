import Foundation

/// Navigation value for the "See All" screens behind each carousel in
/// `PaperDetailView` — carries just enough to load its own list.
struct RelatedPapersDestination: Hashable {
    enum Kind: Hashable {
        case references
        case citedBy
        case related

        var title: String {
            switch self {
            case .references: return "References"
            case .citedBy: return "Cited By"
            case .related: return "Related"
            }
        }

        /// Label for the "N ___" line closing out a fully-loaded list.
        var itemNoun: String {
            switch self {
            case .references: return "references"
            case .citedBy: return "citations"
            case .related: return "papers"
            }
        }

        /// Bibliography numbering, which only References has.
        var numberFor: ((_ index: Int, _ paper: Paper) -> String?)? {
            self == .references ? { index, _ in "[\(index + 1)]" } : nil
        }
    }

    let kind: Kind
    let sourcePaper: Paper

    /// Stores the row-sized copy. This is a navigation value, so it gets
    /// hashed and compared on every push and every path diff, and a full
    /// record drags its whole bibliography along for the ride — which
    /// nothing here reads, since the list refetches by id.
    init(kind: Kind, sourcePaper: Paper) {
        self.kind = kind
        self.sourcePaper = sourcePaper.summary
    }

    /// Pages this destination's papers. The carousel on the detail screen
    /// asks `PaperService` for page 1 of the same thing, so opening "See
    /// All" is a cache hit rather than a second round of requests.
    func makePager() -> PaperPager {
        let id = sourcePaper.id
        switch kind {
        case .references:
            return PaperPager { page, size, refresh in
                try await PaperService.shared.references(of: id, page: page, size: size, refresh: refresh)
            }
        case .citedBy:
            return PaperPager { page, size, refresh in
                try await PaperService.shared.citations(of: id, page: page, size: size, refresh: refresh)
            }
        case .related:
            return PaperPager { page, size, refresh in
                let record = try await PaperService.shared.details(id: id, refresh: refresh)
                return try await Recommender.related(
                    to: [record],
                    via: .sharedFoundations,
                    // Ranked purely on the paper, not the reader, and in
                    // ranked order rather than sampled. A carousel is a
                    // handful of suggestions and can afford to be playful;
                    // a list someone opened deliberately should be the
                    // ranking itself, and should stay put while they page
                    // through it.
                    profile: .empty,
                    dailySeed: nil,
                    limit: size,
                    page: page,
                    refresh: refresh
                )
            }
        }
    }
}
