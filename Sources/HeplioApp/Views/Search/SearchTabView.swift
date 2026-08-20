import SwiftUI
import SwiftData

struct SearchTabView: View {
    @State private var query = ""
    /// INSPIRE's own text ranking, which is the only ordering that
    /// answers "which of these did I mean". Sorted by date instead — as
    /// this screen used to be — a search for "dark matter direct
    /// detection" opens on yesterday's uncited preprints out of 8,985
    /// hits, with the canonical papers nowhere in sight.
    @State private var sort: InspireHEPClient.SortOrder = .relevance
    @State private var pager = PaperPager.empty
    /// The last query actually sent. Lets a sort change skip the typing
    /// debounce — waiting 400ms after tapping a menu item feels broken,
    /// while not waiting between keystrokes costs a request each.
    @State private var lastSearched = ""
    /// One per stack, so a title zooms into the detail screen it opens.
    @Namespace private var paperTransition

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecentSearch.searchedAt, order: .reverse) private var recentSearches: [RecentSearch]
    /// Papers reached by searching, the way Music lists what you tapped
    /// through to from a search rather than everything you've ever played.
    @Query(
        // Spelled `== true` rather than as a bare Bool — SwiftData's
        // predicate compilation is fussy about the shorthand.
        filter: #Predicate<ViewedPaper> { $0.fromSearch == true },
        sort: \ViewedPaper.viewedAt,
        order: .reverse
    ) private var recentlyOpened: [ViewedPaper]

    /// Debounce, so typing a query doesn't spend a request per keystroke.
    private static let typingPause = Duration.milliseconds(400)
    /// Enough to jog a memory without turning the idle screen into a list
    /// to scroll.
    private static let recentLimit = 10

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var errorMessage: String? {
        switch pager.loadError {
        case .some(InspireHEPError.rateLimited):
            return "Too many requests right now. Please wait a moment and try again."
        case .some:
            return "Couldn't load results. Check your connection and try again."
        case .none:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    ContentUnavailableView(
                        "Something Went Wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    .listRowSeparator(.hidden)
                } else if trimmedQuery.isEmpty {
                    idleContent
                } else {
                    PapersListView(pager: pager, itemNoun: "results") {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .pagedPapersList(pager)
            .navigationTitle("Search")
            .paperNavigationDestinations()
            // Empty options while the field is empty, so the button only
            // appears once there are results to order.
            .sortToolbarItem($sort, options: trimmedQuery.isEmpty ? [] : .searchOptions)
        }
        // On the stack, not on the List inside it: destinations inherit
        // the stack's environment. Anything pushed from this tab counts as
        // found by searching, and carries the query that found it.
        .environment(\.paperOrigin, .search(query: trimmedQuery))
        .environment(\.paperTransitionNamespace, paperTransition)
        // A full-width field in its own row under the title, rather than
        // whatever `.automatic` decides. Left to itself the system
        // minimizes search into a toolbar button when the bar is busy —
        // and this bar also carries the sort menu — which buries the one
        // control this whole tab exists for. `.always` also stops it
        // collapsing away on scroll. Same placement as the History and
        // author-list screens.
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Papers, authors, keywords"
        )
        .onSubmit(of: .search) {
            modelContext.recordSearch(query)
        }
        // One task over both inputs: typing and changing the sort both
        // mean "run a different search", and two separate `.task(id:)`
        // blocks would each fire on appear and load the same page twice.
        .task(id: Request(query: trimmedQuery, sort: sort)) {
            await search(Request(query: trimmedQuery, sort: sort))
        }
    }

    private struct Request: Hashable {
        let query: String
        let sort: InspireHEPClient.SortOrder
    }

    /// What the tab shows before anything is typed: what was searched for
    /// recently, and what those searches led to.
    @ViewBuilder
    private var idleContent: some View {
        if recentSearches.isEmpty, recentlyOpened.isEmpty {
            ContentUnavailableView(
                "Search Literature",
                systemImage: "magnifyingglass",
                description: Text("Search by author, title, or keyword")
            )
            .listRowSeparator(.hidden)
        } else {
            if !recentSearches.isEmpty {
                Section {
                    ForEach(Array(recentSearches.prefix(Self.recentLimit))) { search in
                        Button {
                            query = search.text
                            modelContext.recordSearch(search.text)
                        } label: {
                            Label(search.text, systemImage: "magnifyingglass")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                modelContext.delete(search)
                            }
                        }
                    }
                } header: {
                    sectionHeader("Recently Searched") {
                        modelContext.clearRecentSearches()
                    }
                }
            }

            if !recentlyOpened.isEmpty {
                Section("Recently Opened") {
                    ForEach(Array(recentlyOpened.prefix(Self.recentLimit))) { viewed in
                        if let paper = viewed.paper {
                            NavigationLink(value: paper) {
                                PaperRowView(paper: paper)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Clear", action: clear)
                .font(.footnote)
                .textCase(nil)
        }
    }

    private func search(_ request: Request) async {
        guard !request.query.isEmpty else {
            pager = .empty
            lastSearched = ""
            return
        }
        // Only the text needs settling. Re-sorting a query that's already
        // on screen should feel like a tap, not like typing.
        if request.query != lastSearched {
            guard (try? await Task.sleep(for: Self.typingPause)) != nil else { return }
        }
        lastSearched = request.query
        await pager.reload(query: request.query, sort: request.sort)
    }
}

#Preview {
    SearchTabView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
