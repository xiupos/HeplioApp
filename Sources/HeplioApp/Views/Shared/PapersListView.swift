import SwiftUI

/// The row content for a `List` of papers driven by a `PaperPager` —
/// shared by `SearchTabView` and `RelatedPapersListView` so both page in
/// results the same way (10 at a time, more once the last few loaded rows
/// scroll into view). Meant to be placed inside the caller's own `List`,
/// which still owns navigation destinations and any screen-specific empty
/// states above this content (e.g. Search's "type to search" prompt).
struct PapersListView<EmptyContent: View>: View {
    let pager: PaperPager
    var numberFor: ((_ index: Int, _ paper: Paper) -> String?)?
    /// Label for the "N ___" summary shown once the last page has loaded,
    /// e.g. "papers" → "17 papers", "citations" → "17 citations".
    var itemNoun: String = "papers"
    @ViewBuilder var emptyContent: () -> EmptyContent

    var body: some View {
        switch pager.phase {
        case .idle:
            EmptyView()
        case .loading:
            PagerLoadingRow()
        case .failed:
            PagerFailureRow(error: pager.loadError)
        case .empty:
            emptyContent()
                .listRowSeparator(.hidden)
        case .content:
            ForEach(Array(pager.papers.enumerated()), id: \.element.id) { index, paper in
                row(for: paper, number: numberFor?(index, paper))
                    .onAppear {
                        Task { await pager.loadMoreIfNeeded(currentItem: paper) }
                    }
            }
            PagerFooter(pager: pager, itemNoun: itemNoun)
        }
    }

    @ViewBuilder
    private func row(for paper: Paper, number: String?) -> some View {
        if paper.hasInspireRecord {
            NavigationLink(value: paper) {
                PaperRowView(paper: paper, number: number)
            }
        } else if let externalLinkURL = paper.externalLinkURL {
            Link(destination: externalLinkURL) {
                PaperRowView(paper: paper, number: number, showsExternalLinkIndicator: true)
            }
        } else {
            PaperRowView(paper: paper, number: number, showsExternalLinkIndicator: true)
        }
    }
}

extension View {
    /// The chrome every paged list of papers shares: flat rows and
    /// pull-to-refresh.
    ///
    /// Loading is deliberately *not* in here. A fixed source loads once
    /// (`.task { loadInitialIfNeeded() }`); a sortable one reloads
    /// whenever the ordering changes (`.task(id: sort)`). Bundling one of
    /// those in would silently do the wrong thing for the other, which is
    /// exactly the bug this modifier used to hide.
    func pagedPapersList(_ pager: PaperPager) -> some View {
        listStyle(.plain)
            .refreshable { await pager.refresh() }
    }
}
