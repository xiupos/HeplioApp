import SwiftUI

/// The rows every paged list shows when it isn't showing papers: the
/// spinner while a page is in flight, the failure state, and the count
/// that closes out a fully-loaded list.
///
/// They live here because `PapersListView` and `HeadlineFeedView` render
/// the same things from the same `PaperPager`, and the New tab needs its
/// own row layout so it can't simply use `PapersListView`. The wording of
/// a load failure is the part most worth keeping identical — a reader who
/// meets it on Search and again on New shouldn't be told two different
/// things about the same dropped connection.
///
/// Each carries `.listRowSeparator(.hidden)` itself, since every caller
/// is inside a `List` and would otherwise have to remember to.
private extension View {
    func pagerStateRow() -> some View {
        frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
    }
}

struct PagerLoadingRow: View {
    var body: some View {
        ProgressView().pagerStateRow()
    }
}

struct PagerFailureRow: View {
    var error: Error?

    var body: some View {
        ContentUnavailableView(
            error.isRateLimited ? "Too Many Requests" : "Couldn't Load",
            systemImage: error.isRateLimited ? "clock.badge.exclamationmark" : "exclamationmark.triangle",
            description: Text(error.loadFailureAdvice)
        )
        .pagerStateRow()
    }
}

extension Error {
    /// INSPIRE allows 15 requests per 5 seconds and a blocked request
    /// still counts against the quota, so this is a state a reader can
    /// actually reach — Home in particular spends a request per shelf as
    /// they scroll. Telling them to check their connection when the
    /// network is fine sends them the wrong way, so the two failures are
    /// named apart everywhere, rather than only on Search where the
    /// distinction happened to be written first.
    var isRateLimited: Bool {
        // Cast first: `Error` is an existential, so an enum-case pattern
        // can't be matched against it directly.
        guard let inspire = self as? InspireHEPError else { return false }
        if case .rateLimited = inspire { return true }
        return false
    }

    var loadFailureAdvice: String {
        isRateLimited ? LoadFailure.rateLimited : LoadFailure.generic
    }
}

/// The same two, for the `loadError?` a `PaperPager` publishes. A missing
/// error isn't a rate limit, and its advice is the ordinary one.
extension Optional where Wrapped == Error {
    var isRateLimited: Bool { self?.isRateLimited ?? false }
    var loadFailureAdvice: String { self?.loadFailureAdvice ?? LoadFailure.generic }
}

private enum LoadFailure {
    static let generic = "Check your connection and try again."
    static let rateLimited = "INSPIRE-HEP is limiting requests. Wait a moment and try again."
}

/// The footer under a paged list: a spinner while the next page loads,
/// then a count once there is no next page. Nothing at all in between,
/// which is what stops a half-scrolled list from claiming a total it
/// hasn't reached.
struct PagerFooter: View {
    let pager: PaperPager
    /// How to describe the total, e.g. "17 results" or "17 papers in the
    /// last 14 days". A closure rather than a plain noun because New
    /// qualifies its count with the window it covers.
    let label: (Int) -> String
    /// New's rows run edge to edge with their insets zeroed, so its
    /// footer has to space itself; a list with ordinary row insets
    /// already has the room. Not unified, because doing so would silently
    /// respace every existing list.
    var verticalPadding: CGFloat = 0

    init(pager: PaperPager, itemNoun: String, verticalPadding: CGFloat = 0) {
        self.init(pager: pager, verticalPadding: verticalPadding) { "\($0) \(itemNoun)" }
    }

    init(
        pager: PaperPager,
        verticalPadding: CGFloat = 0,
        label: @escaping (Int) -> String
    ) {
        self.pager = pager
        self.label = label
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        if pager.isLoadingMore {
            ProgressView()
                .padding(.vertical, verticalPadding)
                .pagerStateRow()
        } else if pager.reachedEnd {
            Text(label(pager.papers.count))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, verticalPadding)
                .pagerStateRow()
        }
    }
}
