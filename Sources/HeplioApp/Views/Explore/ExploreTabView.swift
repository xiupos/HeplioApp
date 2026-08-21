import SwiftUI

/// The catalog: where to start when you don't have something specific to
/// look up. Search's counterpart, and deliberately impersonal — nothing
/// here depends on what you've read.
///
/// A `ScrollView` rather than a `List`, for the same reason
/// `PaperDetailView` is one: every tile and every card is a
/// `NavigationLink`, and a `List` row holding several siblings
/// mis-manages them and staples its own disclosure chevron onto each.
///
/// Grids rather than rows because these are peers, not a settings menu.
/// `.adaptive` columns give two on iPhone and four or five on iPad,
/// which is the difference between filling an iPad's width and drawing
/// one 900-point-wide row per category.
struct ExploreTabView: View {
    /// The only thing on this screen that costs a request, and it loads
    /// when the screen does. Everything below it is a static table —
    /// worth keeping that way, since a carousel per shelf would spend the
    /// entire 15 requests / 5s window before anything is scrolled.
    @State private var trending: LoadState<[Paper]> = .loading

    /// One per stack, so a Trending card's title zooms into the detail
    /// screen it opens.
    @Namespace private var paperTransition

    private static let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PaperCarouselView(
                        title: BrowseTopic.trending.title,
                        icon: "flame",
                        destination: BrowseTopic.trending,
                        state: trending
                    )
                    .shelfPanel()

                    gridShelf(title: "Categories", icon: "square.grid.2x2", topics: BrowseTopic.categories)
                    gridShelf(title: "Collaborations", icon: "person.3", topics: BrowseTopic.collaborations)
                    gridShelf(title: "Collections", icon: "books.vertical", topics: BrowseTopic.collections)
                }
                .padding(.vertical)
            }
            .navigationTitle("Explore")
            .paperNavigationDestinations()
            // `.task` re-runs whenever this screen re-appears, and popping
            // a pushed paper back off counts — so this asks only once per
            // visit to the tab, rather than re-deciding the shelf under a
            // reader who is on their way back to where they were.
            .task {
                guard trending.value == nil else { return }
                trending = await .load {
                    try await PaperService.shared.search(
                        query: BrowseTopic.trending.query,
                        sort: BrowseTopic.trending.defaultSort
                    )
                }
            }
        }
        .environment(\.paperTransitionNamespace, paperTransition)
    }

    private func gridShelf(title: String, icon: String, topics: [BrowseTopic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(topics, id: \.self) { topic in
                    NavigationLink(value: topic) {
                        BrowseTileView(topic: topic)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .shelfPanel()
    }
}

#Preview {
    ExploreTabView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
