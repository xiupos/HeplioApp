import SwiftUI

/// Everything one author has written, newest first. An author lookup is
/// just another INSPIRE query, so this is the same `PaperPager` +
/// `PapersListView` as Search — and it shares Search's cache entries too,
/// since both go through `PaperService.search`.
struct AuthorPapersView: View {
    let author: Paper.Author

    /// Newest first by default — an author page is usually "what have
    /// they been doing lately". Most Cited answers the other question
    /// people ask of a name, which is what they're known for.
    @State private var sort: InspireHEPClient.SortOrder = .mostRecent
    @State private var pager = PaperPager.empty

    var body: some View {
        List {
            PapersListView(pager: pager, itemNoun: "papers") {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("INSPIRE-HEP doesn't list any papers for this author.")
                )
            }
        }
        .pagedPapersList(pager)
        .navigationTitle(author.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sortToolbarItem($sort, options: .browseOptions)
        .toolbar {
            if let inspireURL = author.inspireURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: inspireURL) {
                        Label("INSPIRE-HEP", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .task(id: sort) { await pager.reload(query: author.papersQuery, sort: sort) }
    }
}

#Preview {
    NavigationStack {
        AuthorPapersView(author: Paper.preview.authors[0])
    }
    .modelContainer(for: LibraryStore.models, inMemory: true)
}
