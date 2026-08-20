import SwiftUI

/// One shelf entry's papers — a category, an experiment, or a document
/// type — as the same paged list Search and the "See All" screens use,
/// plus the sort control that is the whole point of a browse screen.
///
/// Loading is driven by `.task(id: sort)` rather than a one-shot task:
/// changing the sort has to point the pager at a new source, and a
/// `.task` without an id would never re-fire to do it.
struct BrowseListView: View {
    let topic: BrowseTopic

    /// View state only. A browse screen is somewhere you pass through,
    /// not a place with settings to remember, so each push starts at
    /// whatever that topic's default is.
    @State private var sort: InspireHEPClient.SortOrder
    @State private var pager = PaperPager.empty

    init(topic: BrowseTopic) {
        self.topic = topic
        _sort = State(initialValue: topic.defaultSort)
    }

    var body: some View {
        List {
            PapersListView(pager: pager, itemNoun: topic.itemNoun) {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("INSPIRE-HEP doesn't list anything here yet.")
                )
            }
        }
        .pagedPapersList(pager)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .sortToolbarItem($sort, options: .browseOptions)
        // Switching the sort reloads from page one rather than re-sorting
        // what's loaded: the ordering is INSPIRE's, and page 4 of "most
        // cited" has nothing to do with page 4 of "most recent".
        .task(id: sort) { await pager.reload(query: topic.query, sort: sort) }
    }
}

#Preview {
    NavigationStack {
        BrowseListView(topic: .category(.hepPh))
    }
    .modelContainer(for: LibraryStore.models, inMemory: true)
}
