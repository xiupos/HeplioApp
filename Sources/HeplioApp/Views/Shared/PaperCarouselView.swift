import SwiftUI

/// A titled, horizontally-scrolling row of `PaperCardView`s with an
/// optional "See All" link in the header — Music/News' "You Might Also
/// Like" treatment. Used by `PaperDetailView`'s References/Cited By/
/// Related carousels, Explore's Trending shelf, and every shelf on Home.
///
/// Not embedded in a `List`, deliberately: a `NavigationLink` inside a
/// `List` row gets its own auto-added disclosure chevron on top of any
/// chevron drawn here, and `List` mis-manages multiple sibling
/// `NavigationLink`s sharing one row. A plain `ScrollView` sidesteps both.
///
/// **Home is a `List` and uses this anyway, which is what `onSelect` and
/// `onSeeAll` are for.** That tab has to paginate, and paginating inside
/// a `LazyVStack` is the bug the New tab was rewritten to escape — so
/// Home takes New's side and its way out with it: hand this view closures
/// instead of navigation values, and it builds `Button`s that append to
/// the caller's `NavigationPath`. No `NavigationLink` in the row, nothing
/// for `List` to decorate or mis-manage. Callers that aren't inside a
/// `List` pass `destination:` as before and are unaffected.
///
/// `Destination` is generic because "See All" leads somewhere different
/// depending on who's asking — a `RelatedPapersDestination` from the
/// detail screen, a `BrowseTopic` from Explore. Both are just navigation
/// values registered in `paperNavigationDestinations()`.
struct PaperCarouselView<EmptyContent: View, Destination: Hashable>: View {
    let title: String
    /// A second, quieter line under the title. Home uses it to say *why*
    /// a shelf is on the screen ("Because You Read" over the paper's own
    /// title), which is the difference between a personal shelf and one
    /// of Explore's.
    var subtitle: String? = nil
    /// Leading glyph on the header, e.g. Explore's "Trending" carousel.
    /// Optional and unused by `PaperDetailView`'s own carousels, which
    /// keep their plain-text headers.
    var icon: String? = nil
    var destination: Destination?
    /// Carries its own loading/failure state so each carousel fills in as
    /// its own page arrives, independently of the screen around it.
    let state: LoadState<[Paper]>
    var numberFor: ((_ index: Int, _ paper: Paper) -> String?)?
    /// Set by callers inside a `List` — see the note above. Takes
    /// precedence over the `NavigationLink` path.
    var onSelect: ((Paper) -> Void)? = nil
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var emptyContent: () -> EmptyContent

    private var papers: [Paper] { state.value ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if state.isLoading {
                        ProgressView()
                            .frame(width: 180, height: 148)
                    } else if papers.isEmpty {
                        emptyContent()
                    } else {
                        ForEach(Array(papers.enumerated()), id: \.element.id) { index, paper in
                            card(for: paper, number: numberFor?(index, paper))
                        }
                    }
                }
                .padding(.horizontal)
                // Room for the cards' own shadow — a ScrollView otherwise
                // clips it flush against the card's bottom edge.
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if let onSeeAll {
            Button(action: onSeeAll) { disclosingHeader }
                .buttonStyle(.plain)
        } else if let destination {
            NavigationLink(value: destination) { disclosingHeader }
                .buttonStyle(.plain)
        } else {
            headerLabel
        }
    }

    private var disclosingHeader: some View {
        HStack(spacing: 6) {
            headerLabel
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Deliberately not a `Label`: `Label`'s default style reserves an
    /// icon column sized to the widest glyph the environment has seen,
    /// which is generous enough at `.headline` to read as a stray gap
    /// after a short title like "For You" — `TightLabelStyle` exists for
    /// this same reason at smaller sizes. Building the icon and the text
    /// block by hand also lets the icon center against *both* lines when
    /// there's a subtitle, and keeps the subtitle's left edge under the
    /// title's rather than under the icon's.
    private var headerLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for paper: Paper, number: String?) -> some View {
        if let onSelect, paper.hasInspireRecord {
            Button { onSelect(paper) } label: {
                PaperCardView(paper: paper, number: number)
            }
            .buttonStyle(.plain)
        } else if paper.hasInspireRecord {
            // `ZoomedPaper`, not `paper`: a card grows into the detail
            // screen, where a `PaperRowView` pushes it the ordinary way.
            NavigationLink(value: ZoomedPaper(paper)) {
                PaperCardView(paper: paper, number: number)
            }
            .buttonStyle(.plain)
        } else if let externalLinkURL = paper.externalLinkURL {
            Link(destination: externalLinkURL) {
                PaperCardView(paper: paper, number: number)
            }
            .buttonStyle(.plain)
        } else {
            PaperCardView(paper: paper, number: number)
        }
    }
}

extension PaperCarouselView where EmptyContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        destination: Destination? = nil,
        state: LoadState<[Paper]>,
        numberFor: ((_ index: Int, _ paper: Paper) -> String?)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            destination: destination,
            state: state,
            numberFor: numberFor
        ) {
            EmptyView()
        }
    }
}

extension PaperCarouselView where EmptyContent == EmptyView, Destination == AnyHashable {
    /// The closure-driven form, for callers inside a `List`.
    ///
    /// `Destination` is pinned to `AnyHashable` and left nil purely so the
    /// generic can be inferred at a call site that never mentions it —
    /// Swift has no way to give a generic parameter a default. Nothing is
    /// ever pushed through it on this path; `onSeeAll` is.
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        state: LoadState<[Paper]>,
        onSelect: @escaping (Paper) -> Void,
        onSeeAll: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            destination: nil,
            state: state,
            numberFor: nil,
            onSelect: onSelect,
            onSeeAll: onSeeAll
        ) {
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            PaperCarouselView(
                title: "References",
                destination: RelatedPapersDestination(kind: .references, sourcePaper: .preview),
                state: .loaded([.preview, .preview])
            )
        }
    }
}
