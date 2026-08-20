import SwiftUI

/// Where the reader reached a paper from. Carried in the environment
/// because the push itself is a plain `NavigationLink(value:)` deep inside
/// a shared row view — the tab it happened in is context, not something a
/// row should have to pass along.
///
/// Set it on the `NavigationStack` itself, not on a view inside it:
/// pushed destinations inherit the stack's environment, not that of the
/// subview the `.navigationDestination` happens to be attached to.
enum PaperOrigin: Hashable {
    case browsing
    /// Reached from search results, carrying the query that found it —
    /// opening a result is the clearest sign a query was worth
    /// remembering, so it's recorded then as well as on submit.
    case search(query: String)

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }

    var searchQuery: String? {
        if case let .search(query) = self { return query }
        return nil
    }
}

extension EnvironmentValues {
    @Entry var paperOrigin: PaperOrigin = .browsing
}
