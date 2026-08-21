import SwiftUI
import SwiftData

/// The front door: shelves built out of what this reader has read.
///
/// Home is *you*, New is *time*, Explore is *everything that isn't you* —
/// so nothing on this screen is here because it's popular. The two
/// impersonal shelves that do appear (Trending, "New This Fortnight") are
/// variety and cold-start material, and `HomeShelfStream` keeps them out
/// of the top.
///
/// **It scrolls as far as there is material.** The shelf *list* is what
/// paginates, not the papers in any one shelf: topics, authors and the
/// reader's own library are each deep enough to keep going, so Home ends
/// where those run out rather than at a fixed number of rows.
///
/// **A `List`, for the reason the New tab is one.** Both screens
/// paginate, and a paginating `ScrollView` + `LazyVStack` estimates the
/// height of rows it hasn't built and corrects itself the moment one
/// appears, which drags the content offset out from under the reader.
/// The usual objection to a `List` — it mis-manages sibling
/// `NavigationLink`s in a row and staples chevrons onto them — is
/// answered the same way New answered it: there are no `NavigationLink`s
/// here at all, only `Button`s appending to the path below.
struct HomeTabView: View {
    @Environment(\.modelContext) private var context

    /// The reader's stated interest, shared with the New tab's chip. On a
    /// first launch it's the only thing this screen knows about them, and
    /// it decides what Home opens on.
    @AppStorage("newFeedSelection") private var newFeedSelectionID: String = ""

    @State private var profile: ReadingProfile = .empty
    @State private var stream: HomeShelfStream?
    @State private var visibleCount = HomeShelfStream.pageSize * 2
    @State private var reloadToken = 0
    @State private var path = NavigationPath()

    /// One per stack, so a card grows into the detail screen it opens.
    @Namespace private var paperTransition

    private var shelves: [HomeShelf] {
        Array((stream?.shelves ?? []).prefix(visibleCount))
    }

    private var reachedEnd: Bool { visibleCount >= (stream?.shelves.count ?? 0) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if stream == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(shelves) { shelf in
                        HomeShelfView(
                            shelf: shelf,
                            profile: profile,
                            path: $path,
                            reloadToken: reloadToken
                        )
                        // No insets and no separator: what's on screen is
                        // this run of shelves, not `List`'s idea of one.
                        // The gap under each shelf is drawn inside the row
                        // — see `HomeShelfView` — so that a shelf which
                        // turns out to be empty leaves no trace.
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear { revealMore(after: shelf) }
                    }
                    footer
                }
            }
            .listStyle(.plain)
            .navigationTitle("Home")
            .paperNavigationDestinations()
            .refreshable { await refresh() }
            // Guarded, because `.task` re-runs every time this screen
            // re-appears and popping a paper back off counts as
            // re-appearing. Rebuilding the stream there would re-deal the
            // whole screen under a reader who is on their way back to
            // where they were — the same bug `PaperPager.reload` and
            // Explore's Trending task each carry a guard against.
            .task {
                guard stream == nil else { return }
                rebuild()
            }
        }
        .environment(\.paperTransitionNamespace, paperTransition)
    }

    @ViewBuilder
    private var footer: some View {
        if !reachedEnd {
            // A spinner and nothing more. It deliberately does *not*
            // also trigger the next page the way the New tab's sentinel
            // row does: revealing more shelves makes this footer appear
            // again a moment later, which would let one scroll to the
            // bottom cascade into revealing the entire stream and firing
            // every request in it at once. The last shelf's own
            // `.onAppear` is the single trigger, and it advances one page
            // per render — including through shelves that turn out to be
            // empty, since the next one then becomes the last.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
        } else if profile.isEmpty {
            // The cold start says what would change, once — not as an
            // empty state above an empty screen, but as a footer under a
            // screen that already has plenty on it.
            Text("Save and open papers, and Home starts following your reading.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
        }
    }

    private func revealMore(after shelf: HomeShelf) {
        guard shelf == shelves.last else { return }
        visibleCount += HomeShelfStream.pageSize
    }

    /// Rebuilds the profile and today's shelves from the store.
    ///
    /// The profile is *computed*, never stored: it's a fold over the
    /// library and the history, and both of those are what will sync over
    /// iCloud. Nothing derived is kept, so there is no algorithm state to
    /// migrate or reconcile when that's turned on, and a fresh device
    /// gets the right Home the moment the records land. See
    /// `ReadingProfile`.
    private func rebuild() {
        let profile = context.readingProfile()
        self.profile = profile
        self.stream = HomeShelfStream(
            profile: profile,
            preferredCategory: ArxivCategory(rawValue: newFeedSelectionID)
        )
    }

    /// Pull-to-refresh. Picks up anything saved or read since the screen
    /// was built, and tells every shelf to go past `ResponseCache`.
    ///
    /// The shelf *order* deliberately doesn't change: it's a function of
    /// today's date, and "today" is the same after a pull as before it.
    /// What refreshes is what's on the shelves.
    private func refresh() async {
        rebuild()
        reloadToken += 1
    }
}

#Preview {
    HomeTabView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
