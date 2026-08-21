import SwiftUI
import SwiftData

/// One row of Home: a shelf, filled in.
///
/// Every shelf loads itself, independently of the ones around it, so the
/// screen fills in shelf by shelf instead of waiting on its slowest row —
/// the same arrangement `PaperDetailView` uses for its three carousels.
/// What a shelf costs varies from a request to nothing at all, and
/// `HomeShelf.needsNetwork` is what lets `HomeShelfStream` interleave the
/// two kinds so a page is never all requests.
///
/// **Nothing here is a `NavigationLink`.** Home is a `List`, and a `List`
/// row full of sibling links is mis-managed and chevron-stapled — so
/// every tap appends to the path this view is handed, exactly as the New
/// tab's headlines do. See `PaperCarouselView`.
struct HomeShelfView: View {
    let shelf: HomeShelf
    /// Rebuilt by `HomeTabView` per appearance and passed down rather than
    /// recomputed per shelf: it's cheap, but not forty-times-per-screen
    /// cheap.
    let profile: ReadingProfile
    @Binding var path: NavigationPath
    /// Bumped by pull-to-refresh. A change means "go past the cache";
    /// the first load is not a refresh, which is what `loadedToken`
    /// distinguishes.
    let reloadToken: Int

    @Environment(\.modelContext) private var context

    @State private var state: LoadState<[Paper]> = .loading
    @State private var loadedToken: Int?

    private static let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        content
            .task(id: ReloadKey(shelf: shelf, token: reloadToken)) { await load() }
    }

    /// `.task(id:)` re-runs when either half changes: a `List` reusing
    /// this row for a different shelf, or a pull-to-refresh.
    private struct ReloadKey: Hashable {
        let shelf: HomeShelf
        let token: Int
    }

    @ViewBuilder
    private var content: some View {
        switch shelf {
        case .topicsForYou(let topics):
            tileShelf(topics) { topic in
                Button { path.append(topic) } label: { BrowseTileView(topic: topic) }
                    .buttonStyle(.plain)
            }
        case .authorsToFollow(let authors):
            tileShelf(authors) { author in
                Button { path.append(author) } label: { AuthorTileView(author: author) }
                    .buttonStyle(.plain)
            }
        default:
            papersShelf
        }
    }

    /// A shelf that came back empty renders as nothing at all.
    ///
    /// The stream can't know in advance that a reader has nothing saved
    /// under `hep-lat`, or that a quiet collaboration published nothing
    /// this fortnight — and the honest answer to an empty shelf is not an
    /// empty-state placeholder repeated down the page, it's the shelf not
    /// being there.
    ///
    /// The row itself stays, because the `List` needs something to hang
    /// this shelf's identity and its pagination trigger on. The gap under
    /// each shelf is therefore padding *inside* the row rather than a
    /// `listRowInsets`, so an empty one takes up nothing at all rather
    /// than leaving a blank the height of the spacing.
    @ViewBuilder
    private var papersShelf: some View {
        if let papers = state.value, papers.isEmpty {
            EmptyView()
        } else {
            PaperCarouselView(
                title: shelf.title,
                subtitle: shelf.subtitle,
                icon: shelf.icon,
                state: state,
                onSelect: { path.append(ZoomedPaper($0)) },
                onSeeAll: seeAllAction
            )
            .shelfPanel(tinted: shelf.isPersonal)
            .padding(.bottom, Self.shelfSpacing)
        }
    }

    private static let shelfSpacing: CGFloat = 16

    private func tileShelf<T: Hashable, Tile: View>(
        _ items: [T],
        @ViewBuilder tile: @escaping (T) -> Tile
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: shelf.icon ?? "square.grid.2x2")
                Text(shelf.title)
            }
            .font(.headline)
            LazyVGrid(columns: Self.tileColumns, spacing: 12) {
                ForEach(items, id: \.self) { tile($0) }
            }
        }
        .padding(.horizontal)
        .shelfPanel(tinted: shelf.isPersonal)
        .padding(.bottom, Self.shelfSpacing)
    }

    /// Where "See All" goes, or nil for the shelves that are already
    /// everything they have.
    ///
    /// Each of these is a value already registered in
    /// `paperNavigationDestinations()` — the recommendation shelves reuse
    /// the detail screen's own `Related` list, an author shelf reuses
    /// `AuthorPapersView`, a topic shelf reuses `BrowseListView`. Home
    /// adds no destination of its own.
    private var seeAllAction: (() -> Void)? {
        switch shelf {
        case .becauseYouRead(let paper):
            return { path.append(RelatedPapersDestination(kind: .related, sourcePaper: paper)) }
        case .author(let author):
            return { path.append(author) }
        case .topic(let topic, _):
            return { path.append(topic) }
        case .trending:
            return { path.append(BrowseTopic.trending) }
        // "For You" has no wider list to open — it *is* the ranking. The
        // two local shelves are already the whole of what they show, and
        // "New This Fortnight" belongs to a tab, not a push.
        case .forYou, .newAtRandom, .readAgain, .fromLibrary, .topicsForYou, .authorsToFollow:
            return nil
        }
    }

    // MARK: - Loading

    private func load() async {
        // A tile shelf carries its contents in the navigation value
        // itself, so there is nothing to fetch.
        if case .topicsForYou = shelf { return }
        if case .authorsToFollow = shelf { return }

        // A first load isn't a refresh, however high the token happens to
        // be by the time a row this far down the page is finally built.
        let refresh = loadedToken.map { $0 != reloadToken } ?? false
        loadedToken = reloadToken

        let dice = DailySeed(salt: shelf.seedSalt)

        switch shelf {
        case .readAgain(let category):
            state = .loaded(local(context.unsavedViewedPapers(), in: category, dice: dice))
        case .fromLibrary(let category):
            state = .loaded(local(context.savedPapers(), in: category, dice: dice))

        case .forYou:
            state = await .load {
                try await Recommender.related(
                    to: profile.seeds.map(\.paper),
                    via: .citingWork,
                    profile: profile,
                    dailySeed: dice,
                    refresh: refresh
                )
            }
        case .becauseYouRead(let paper):
            state = await .load {
                // The stored snapshot has no bibliography — `Paper.summary`
                // drops it — and `.sharedFoundations` is nothing but the
                // bibliography. So the full record is fetched first; it's
                // a paper the reader has opened, so it is almost always
                // still in `ResponseCache`.
                let full = try await PaperService.shared.details(id: paper.id, refresh: refresh)
                return try await Recommender.related(
                    to: [full],
                    via: .sharedFoundations,
                    profile: profile,
                    dailySeed: dice,
                    refresh: refresh
                )
            }

        default:
            guard let query = shelf.query else { return }
            state = await .load {
                try await PaperService.shared.search(query: query.text, sort: query.sort, refresh: refresh)
            }
        }
    }

    /// The local shelves, in one place: filter to the category if the
    /// shelf names one, then let the day's dice pick which of them to
    /// feature. Sampling rather than taking the most recent is what stops
    /// "From Your Library" showing the same five bookmarks every morning.
    private func local(_ papers: [Paper], in category: ArxivCategory?, dice: DailySeed) -> [Paper] {
        let pool = category.map { category in
            papers.filter { $0.arxivCategories.contains(category.rawValue) }
        } ?? papers
        return Recommender.featured(from: pool, dailySeed: dice, limit: PaperService.pageSize)
    }
}
