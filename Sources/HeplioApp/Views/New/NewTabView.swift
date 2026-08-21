import SwiftUI

/// What arrived, in the order it arrived. The tab's axis is time: papers
/// are grouped by the day INSPIRE first saw them, newest first, and
/// nothing on this screen ranks or recommends anything — that's Home's
/// job, and keeping the two apart is the whole reason New exists
/// separately.
///
/// The only choice on offer is which corner of the literature to watch,
/// and it's an explicit one. Chips, not inference.
struct NewTabView: View {
    /// Remembered across launches the way Music remembers where you were.
    /// Stored as the raw id rather than the enum so an unknown value —
    /// written by a build carrying a category this one doesn't — falls
    /// back to "All" instead of failing to decode.
    @AppStorage("newFeedSelection") private var selectionID: String = ""

    @State private var pager = PaperPager.empty
    /// Explicit, because a headline is a `Button` rather than a
    /// `NavigationLink` — `HeadlineFeedView` is a `List`, and keeping the
    /// links out of its rows is what keeps `List` from decorating them.
    @State private var path = NavigationPath()
    /// The feed's own width, watched so the column count can follow it.
    /// Starts at zero, which reads as one column — the right thing to
    /// draw for the one frame before the real width arrives.
    @State private var feedWidth: CGFloat = 0

    /// One per stack, so a headline — and the carousels on the paper it
    /// opens — zoom the way they do everywhere else.
    @Namespace private var paperTransition

    private var selection: NewFeedSelection { NewFeedSelection(id: selectionID) }

    /// How narrow a column of newsprint is allowed to get.
    private static let minimumColumnWidth: CGFloat = 320
    private static let maximumColumnCount = 5

    /// Measured rather than taken from the size class, which only knows
    /// "phone-ish" and "iPad-ish" and so has no way to say two. Read off
    /// the scroll view itself with `onGeometryChange` rather than by
    /// wrapping it in a `GeometryReader`, which would put a greedy layout
    /// container between the navigation stack and its list.
    private var columnCount: Int {
        max(1, min(Self.maximumColumnCount, Int(feedWidth / Self.minimumColumnWidth)))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                categoryPicker
                Divider()
                HeadlineFeedView(pager: pager, columnCount: columnCount) { paper in
                    // `ZoomedPaper`, not `paper`: a headline grows into the
                    // detail screen the way a card does. The two navigation
                    // values exist because the destination can't tell what
                    // pushed it — see `ZoomedPaper`.
                    path.append(ZoomedPaper(paper))
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    feedWidth = width
                }
            }
            .navigationTitle("New")
            .paperNavigationDestinations()
            // No sort control and no search field, deliberately: a feed
            // sorted by anything but time isn't a feed, and looking
            // something up is what the Search tab is for.
            //
            // `PaperPager.reload` no-ops when the query hasn't changed, so
            // this firing again on the way back from a paper costs nothing
            // and leaves the reader where they were.
            .task(id: selectionID) {
                await pager.reload(query: selection.query, sort: .mostRecent)
            }
        }
        .environment(\.paperTransitionNamespace, paperTransition)
    }

    /// Stock capsule buttons, the way Apple's own apps build a chip row —
    /// filled for the one in effect, outlined for the rest. Above the
    /// feed rather than scrolling with it, so switching corners never
    /// means scrolling back up first.
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewFeedSelection.allCases) { option in
                    chip(for: option)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chip(for option: NewFeedSelection) -> some View {
        // Two branches rather than one styled button: `.bordered` and
        // `.borderedProminent` are different types, so there's nothing to
        // pick between inside a single expression.
        if option.id == selectionID {
            Button(option.label) { selectionID = option.id }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        } else {
            Button(option.label) { selectionID = option.id }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

#Preview {
    NewTabView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
