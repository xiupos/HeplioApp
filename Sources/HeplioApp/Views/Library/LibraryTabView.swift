import SwiftUI
import SwiftData

struct LibraryTabView: View {
    @State private var isShowingHistory = false
    @State private var isShowingSettings = false
    @State private var sort: LibrarySort = .recentlySaved
    @State private var filter = ""
    /// Explicit rather than implicit, so opening a paper from inside the
    /// History sheet can push it here directly.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            // The query itself lives in the child, because `@Query` is
            // configured at init and can't be re-pointed afterwards —
            // passing the sort and the filter down is what lets both
            // controls actually change the fetch rather than re-arranging
            // rows in memory.
            SavedPapersList(sort: sort, filter: filter)
                .navigationTitle("Library")
                .paperNavigationDestinations()
                .sortToolbarItem($sort, options: LibrarySort.allCases)
                .toolbar {
                    // The two app-level entry points, grouped so they read
                    // as one island apart from the sort control.
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            isShowingHistory = true
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $isShowingHistory) {
                    HistoryView()
                        .environment(\.openInLibrary) { paper in
                            isShowingHistory = false
                            path.append(paper)
                        }
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                }
        }
        // Scrolls away with the list, like Music's own library search,
        // rather than pinned open the way the History sheet's is — this
        // is a main tab you mostly browse, not a filter you mostly type.
        .searchable(text: $filter, prompt: "Title or Author")
    }
}

/// The saved list itself. Split out only so its `@Query` can be built
/// from the current sort and filter.
private struct SavedPapersList: View {
    let sort: LibrarySort
    /// Kept alongside the query it built, so the empty state can tell
    /// "nothing saved" from "nothing matched".
    private let filter: String
    @Query private var savedPapers: [SavedPaper]

    @Environment(\.modelContext) private var modelContext

    init(sort: LibrarySort, filter: String) {
        self.sort = sort
        let text = filter.trimmingCharacters(in: .whitespaces)
        self.filter = text
        // Matched against the stored columns, not the JSON snapshot,
        // which SwiftData can't see into. `localizedStandardContains` is
        // the case- and diacritic-insensitive comparison Finder uses.
        let predicate = #Predicate<SavedPaper> { saved in
            text.isEmpty
                || saved.title.localizedStandardContains(text)
                || saved.firstAuthor.localizedStandardContains(text)
        }
        _savedPapers = Query(filter: predicate, sort: sort.descriptors)
    }

    var body: some View {
        List {
            if savedPapers.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            } else {
                ForEach(savedPapers) { saved in
                    if let paper = saved.paper {
                        NavigationLink(value: paper) {
                            PaperRowView(paper: paper)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                                modelContext.delete(saved)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// Two different nothings: an empty library, and a search that found
    /// none of it.
    @ViewBuilder
    private var emptyState: some View {
        if filter.isEmpty {
            ContentUnavailableView(
                "No Saved Papers",
                systemImage: "bookmark",
                description: Text("Bookmark papers you're interested in to see them here")
            )
        } else {
            ContentUnavailableView.search(text: filter)
        }
    }
}

#Preview {
    LibraryTabView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
