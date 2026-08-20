import Foundation

/// How the Library orders what you've saved.
///
/// Unrelated to `InspireHEPClient.SortOrder`, deliberately: that one asks
/// INSPIRE to rank a query, this one is a `SortDescriptor` over local
/// SwiftData columns. They share a menu shape and nothing else, and
/// merging them would mean a "Relevance" option over a list with no query
/// and a "Recently Saved" option INSPIRE has never heard of.
enum LibrarySort: String, CaseIterable, SortOption {
    case recentlySaved
    case title
    case year
    case citations

    var label: String {
        switch self {
        case .recentlySaved: return "Recently Saved"
        case .title: return "Title"
        case .year: return "Year"
        // Named for what it actually is. The count is whatever the paper
        // had when it was saved — see `SavedPaper.citationCount` — and a
        // bare "Citations" would imply a live number.
        case .citations: return "Citations as Saved"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlySaved: return "clock"
        case .title: return "textformat"
        case .year: return "calendar"
        case .citations: return "quote.bubble"
        }
    }

    /// Title is the tiebreaker everywhere it isn't the key itself, so
    /// papers sharing a year or a citation count keep a stable order
    /// instead of shuffling between launches.
    var descriptors: [SortDescriptor<SavedPaper>] {
        switch self {
        case .recentlySaved:
            return [SortDescriptor(\.savedAt, order: .reverse)]
        case .title:
            return [SortDescriptor(\.title)]
        case .year:
            return [SortDescriptor(\.year, order: .reverse), SortDescriptor(\.title)]
        case .citations:
            return [SortDescriptor(\.citationCount, order: .reverse), SortDescriptor(\.title)]
        }
    }
}
