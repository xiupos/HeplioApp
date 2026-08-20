import SwiftUI
import SwiftData

/// Recently opened papers, presented as a sheet from the Library tab's
/// clock button. Its own `NavigationStack`, so a paper can be pushed
/// without dismissing the sheet first.
struct HistoryView: View {
    @Query(sort: \ViewedPaper.viewedAt, order: .reverse) private var viewedPapers: [ViewedPaper]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Filters what's already here — it never queries INSPIRE, so unlike
    /// the Search tab's field it isn't recorded as a recent search.
    @State private var filter = ""

    /// Decoded once and narrowed in memory: history is capped at
    /// `ViewedPaper.limit`, so there's nothing to gain from making the
    /// `@Query` predicate dynamic (which would mean pushing the text into
    /// a child view's initializer). The Library tab, which has no cap,
    /// would want the opposite.
    private var matches: [(entry: ViewedPaper, paper: Paper)] {
        let entries = viewedPapers.compactMap { entry in
            entry.paper.map { (entry: entry, paper: $0) }
        }
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return entries }
        return entries.filter {
            $0.paper.title.localizedCaseInsensitiveContains(text)
                || $0.paper.authorsSummaryLine.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if viewedPapers.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Papers you open show up here")
                    )
                    .listRowSeparator(.hidden)
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: filter)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(matches, id: \.entry.id) { viewed, paper in
                        NavigationLink(value: paper) {
                            PaperRowView(paper: paper)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                modelContext.delete(viewed)
                            }
                        }
                    }
                }
            }
            .searchable(
                text: $filter,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Title or Author"
            )
            // Settings (its sibling sheet off the same toolbar) is a
            // `Form`, which is grouped by default — matching here keeps
            // the two utility sheets visually consistent, unlike the
            // flat/white `.plain` style the main tabs use for their lists.
            .listStyle(.insetGrouped)
            // `.insetGrouped`'s default section spacing leaves a wide gap
            // under the search field, which reads as loose in a compact
            // sheet — tighter fits a single-section list like this one.
            .listSectionSpacing(.compact)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .paperNavigationDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) {
                        modelContext.clearHistory()
                    }
                    .disabled(viewedPapers.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
