import SwiftUI

/// A titled, horizontally-scrolling row of `PaperCardView`s with an
/// optional "See All" link in the header — Music/News' "You Might Also
/// Like" treatment. Used by `PaperDetailView`'s References/Cited By/
/// Related carousels; written to be reusable for Home's future
/// recommendation rows too.
///
/// Not embedded in a `List`, deliberately: a `NavigationLink` inside a
/// `List` row gets its own auto-added disclosure chevron on top of any
/// chevron drawn here, and `List` mis-manages multiple sibling
/// `NavigationLink`s sharing one row. A plain `ScrollView` sidesteps both.
///
/// `Destination` is generic because "See All" leads somewhere different
/// depending on who's asking — a `RelatedPapersDestination` from the
/// detail screen, a `BrowseTopic` from Explore. Both are just navigation
/// values registered in `paperNavigationDestinations()`.
struct PaperCarouselView<EmptyContent: View, Destination: Hashable>: View {
    let title: String
    /// Leading glyph on the header, e.g. Explore's "Trending" carousel.
    /// Optional and unused by `PaperDetailView`'s own carousels, which
    /// keep their plain-text headers.
    var icon: String? = nil
    var destination: Destination?
    /// Carries its own loading/failure state so each carousel fills in as
    /// its own page arrives, independently of the screen around it.
    let state: LoadState<[Paper]>
    var numberFor: ((_ index: Int, _ paper: Paper) -> String?)?
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
        if let destination {
            NavigationLink(value: destination) {
                HStack(spacing: 4) {
                    titleLabel
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            titleLabel
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let icon {
            Label(title, systemImage: icon)
                .font(.headline)
        } else {
            Text(title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func card(for paper: Paper, number: String?) -> some View {
        if paper.hasInspireRecord {
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
        icon: String? = nil,
        destination: Destination? = nil,
        state: LoadState<[Paper]>,
        numberFor: ((_ index: Int, _ paper: Paper) -> String?)? = nil
    ) {
        self.init(title: title, icon: icon, destination: destination, state: state, numberFor: numberFor) {
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
