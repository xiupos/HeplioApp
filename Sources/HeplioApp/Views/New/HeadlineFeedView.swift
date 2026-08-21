import SwiftUI

/// The New tab's body: a date-ordered run of headlines, cut into day
/// sections and set in newspaper columns.
///
/// Three structural choices here are all scar tissue from bugs seen on
/// device, and CLAUDE.md's "New" section records what each one cost.
/// In short:
///
/// - **A `List`, never a `ScrollView` + `LazyVStack`.** A lazy stack has
///   to estimate the height of rows it hasn't built, and corrects the
///   estimate as they materialise, which moves the content offset out
///   from under the reader.
/// - **Flat day-header rows, never `Section`.** `Section` brought both
///   ghost separators and an `onAppear` that stopped firing, which
///   silently stalled pagination.
/// - **`Rectangle` rules, never `Divider()`.** See `rule(_:)`.
///
/// What `List` was avoided for in the first place is handled rather than
/// traded away: there are no `NavigationLink`s in the feed at all, just
/// `Button`s calling `onSelect`, so there is nothing for `List` to
/// decorate with a chevron or mis-manage as siblings. Rows run edge to
/// edge with the system separators hidden, so what's on screen is this
/// grid and not `List`'s idea of one. Pull-to-refresh comes back for free.
struct HeadlineFeedView: View {
    let pager: PaperPager
    /// How many headlines sit side by side. Decided by the caller from the
    /// measured width, because it also decides where the rules go.
    let columnCount: Int
    /// A closure rather than a `NavigationLink`, so the rows stay free of
    /// anything `List` wants to style.
    let onSelect: (Paper) -> Void

    @Environment(\.displayScale) private var displayScale

    /// `columnCount` comes from a measurement and is never zero, but a
    /// `stride(by: 0)` would hang rather than merely misdraw — and the
    /// cutting and the blank-filling below have to agree on one number
    /// for a short last row to line up.
    private var columns: Int { max(columnCount, 1) }

    var body: some View {
        List {
            switch pager.phase {
            case .idle:
                EmptyView()
            case .loading:
                PagerLoadingRow()
            case .failed:
                PagerFailureRow(error: pager.loadError)
            case .empty:
                ContentUnavailableView(
                    "Nothing New",
                    systemImage: "calendar.badge.clock",
                    description: Text("No papers were posted here in the last \(NewFeedSelection.windowDays) days.")
                )
                .listRowSeparator(.hidden)
            case .content:
                days
                sentinel
                PagerFooter(pager: pager, verticalPadding: 24) { count in
                    "\(count) papers in the last \(NewFeedSelection.windowDays) days"
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await pager.refresh() }
    }

    private var days: some View {
        ForEach(pager.papers.groupedByDay()) { day in
            Text(day.title)
                .font(.title3.weight(.bold))
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            ForEach(rows(of: day.papers)) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: HeadlineRow) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(row.papers.enumerated()), id: \.element.id) { index, paper in
                    if index > 0 { rule(.vertical) }
                    Button {
                        onSelect(paper)
                    } label: {
                        HeadlineView(paper: paper)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        Task { await pager.loadMoreIfNeeded(currentItem: paper) }
                    }
                }
                // A short last row keeps its columns the width of every
                // other row's rather than stretching one headline across
                // the page. No rule before the blanks: a line into empty
                // space reads as a missing story.
                if row.papers.count < columns {
                    ForEach(row.papers.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            rule(.horizontal)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// A hairline, drawn rather than asked for.
    ///
    /// **Not `Divider()`.** `Divider()` infers its orientation from the
    /// stack it is a *direct* child of, and the between-column rule sits
    /// behind `if index > 0`, which wraps it in `_ConditionalContent` and
    /// loses that context — it then falls back to horizontal. Inside a
    /// `List` row that surfaced as a cluster of stray horizontal lines
    /// under each day, one per gap between columns, inert to the touch.
    /// A `Rectangle` has no orientation to infer, so a conditional can't
    /// break it. `1 / displayScale` keeps it one device pixel, as thin as
    /// the system's own separators.
    private func rule(_ axis: Axis) -> some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(
                width: axis == .vertical ? 1 / displayScale : nil,
                height: axis == .horizontal ? 1 / displayScale : nil
            )
    }

    /// A second, independent pagination trigger behind the last
    /// headline's own `.onAppear`, which is reported often enough as
    /// unreliable inside a `List` not to be trusted alone — it is what
    /// silently stalled the hep-th feed while hep-ex kept paging, with no
    /// error shown anywhere. Nothing about a 1pt row at the very end
    /// depends on column packing or day boundaries the way a headline's
    /// position does. Double-firing is free: `loadNextPage` guards on
    /// `isLoadingMore`.
    @ViewBuilder
    private var sentinel: some View {
        if let last = pager.papers.last {
            Color.clear
                .frame(height: 1)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear {
                    Task { await pager.loadMoreIfNeeded(currentItem: last) }
                }
        }
    }

    private func rows(of papers: [Paper]) -> [HeadlineRow] {
        stride(from: 0, to: papers.count, by: columns).map { start in
            HeadlineRow(papers: Array(papers[start..<min(start + columns, papers.count)]))
        }
    }

    /// A run of headlines sharing one line of the page. Identified by its
    /// first paper, so that appending a page — which only ever re-cuts the
    /// last, partly-filled row of the last day — leaves the rows above it
    /// alone.
    private struct HeadlineRow: Identifiable {
        let papers: [Paper]

        var id: Paper.ID { papers[0].id }
    }
}
