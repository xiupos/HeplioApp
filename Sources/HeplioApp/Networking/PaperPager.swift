import Foundation
import Observation

/// Drives infinite-scroll loading for a `List` of papers, one page at a
/// time, regardless of where the pages actually come from — a search
/// query, a citations lookup, or (for References) enriching a fixed
/// client-side array in slices. The view only needs to call
/// `loadInitialIfNeeded()` once and `loadMoreIfNeeded(currentItem:)` from
/// each row's `.onAppear`.
@Observable
final class PaperPager {
    private(set) var papers: [Paper] = []
    private(set) var isLoadingMore = false
    private(set) var reachedEnd = false
    private(set) var loadError: Error?

    private let pageSize: Int
    private var nextPage = 1
    /// `refresh` is passed along rather than handled here: only
    /// `PaperService` knows which cache entry a page came from, and a
    /// reload that quietly re-reads the cache would look like a no-op.
    ///
    /// `var` rather than `let` so `reload(using:)` can point the same
    /// pager at a new source — see there for why that matters.
    private var fetchPage: (_ page: Int, _ size: Int, _ refresh: Bool) async throws -> [Paper]

    /// Which query/ordering is currently loaded, so `reload(query:sort:)`
    /// can tell "the reader picked something else" from "this screen came
    /// back". See there.
    private var loadedSource: String?

    init(
        pageSize: Int = PaperService.pageSize,
        fetchPage: @escaping (_ page: Int, _ size: Int, _ refresh: Bool) async throws -> [Paper]
    ) {
        self.pageSize = pageSize
        self.fetchPage = fetchPage
    }

    /// A pager with nothing behind it — a placeholder for a screen whose
    /// real query doesn't exist yet (Search before anything is typed) or
    /// whose source isn't built yet (Related, M6).
    static var empty: PaperPager {
        PaperPager { _, _, _ in [] }
    }

    func loadInitialIfNeeded() async {
        guard papers.isEmpty, !reachedEnd, loadError == nil else { return }
        await loadNextPage()
    }

    /// Points this pager at a different source and loads page one — a new
    /// sort order, or a new search query.
    ///
    /// Callers used to build a whole new `PaperPager` and then call
    /// `loadInitialIfNeeded()`. The two happen in one `.task(id:)` body,
    /// but there's a render between them where the new pager exists with
    /// nothing loading yet, which every list reads as "empty, not
    /// loading" — so a fast response could land without a spinner ever
    /// appearing. Here `isLoadingMore` goes up *before* the first
    /// `await`, so that gap can't exist, and it can't be forgotten by the
    /// next screen that adds a sort control either.
    func reload(using source: @escaping (_ page: Int, _ size: Int, _ refresh: Bool) async throws -> [Paper]) async {
        fetchPage = source
        papers = []
        nextPage = 1
        reachedEnd = false
        loadError = nil
        isLoadingMore = true
        do {
            let page = try await fetchPage(1, pageSize, false)
            papers = page
            nextPage = 2
            reachedEnd = page.count < pageSize
            isLoadingMore = false
        } catch is CancellationError {
            // Superseded — another `reload` is already starting and will
            // set its own state. `isLoadingMore` is deliberately left up
            // so the spinner doesn't blink off between two generations of
            // the same switch.
        } catch {
            loadError = error
            isLoadingMore = false
        }
    }

    /// Pull-to-refresh: page one again, from the network. Paging state is
    /// only reset once the new page is actually in hand — resetting up
    /// front and then failing (or being cancelled) would leave the loaded
    /// rows sitting next to a page counter pointing back at them, and the
    /// next scroll would append duplicates.
    func refresh() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(1, pageSize, true)
            papers = page
            nextPage = 2
            reachedEnd = page.count < pageSize
            loadError = nil
        } catch is CancellationError {
            // Superseded; leave what's on screen alone.
        } catch {
            loadError = error
        }
    }

    /// Call from a row's `.onAppear` — the standard "load more when the
    /// last row appears" trigger. Firing earlier (e.g. a few rows before
    /// the end) sounds friendlier, but in practice it means fast requests
    /// finish before the user ever scrolls to the loading footer, so it
    /// only sometimes appears — waiting for the actual last row keeps that
    /// consistent.
    func loadMoreIfNeeded(currentItem: Paper) async {
        guard currentItem.id == papers.last?.id else { return }
        await loadNextPage()
    }

    /// Points this pager at an INSPIRE query at a given ordering — what
    /// every sortable screen in the app actually wants from `reload`.
    /// Search, an author's papers, and each Explore browse list differ
    /// only in the query string they pass here.
    ///
    /// **Asking for what's already loaded does nothing, and that's the
    /// point.** `.task(id:)` re-runs every time its view re-appears, and
    /// popping a pushed detail screen back off counts as re-appearing —
    /// so without this guard, returning from a paper wiped `papers`,
    /// reloaded page one, and dropped the reader at the top of a feed
    /// they were twenty rows down. The marker is cleared when a load
    /// doesn't land (cancelled, or failed), so the next appearance
    /// retries rather than sitting on a spinner forever.
    ///
    /// Pull-to-refresh goes through `refresh()`, which deliberately
    /// doesn't consult this: "give me this same query again" is exactly
    /// what it means.
    func reload(query: String, sort: InspireHEPClient.SortOrder) async {
        let source = "\(sort.rawValue)|\(query)"
        guard source != loadedSource else { return }
        loadedSource = source
        await reload { page, size, refresh in
            try await PaperService.shared.search(
                query: query,
                sort: sort,
                page: page,
                size: size,
                refresh: refresh
            )
        }
        // Nothing to show and not a settled "there is nothing" — the load
        // failed or was cancelled, so forget the marker and let the next
        // appearance try again. A load that *did* land keeps it even if
        // the task was cancelled on the way out: the rows are there, and
        // re-fetching them would throw the reader's place away.
        if papers.isEmpty, !reachedEnd { loadedSource = nil }
    }

    private func loadNextPage() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(nextPage, pageSize, false)
            papers.append(contentsOf: page)
            nextPage += 1
            if page.count < pageSize { reachedEnd = true }
            loadError = nil
        } catch is CancellationError {
            // Superseded by a newer request; leave state untouched.
        } catch {
            loadError = error
        }
    }
}
