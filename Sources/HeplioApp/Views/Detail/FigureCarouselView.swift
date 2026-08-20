import SwiftUI

/// The paper's extracted plots, laid out the way the App Store shows
/// screenshots: a full-bleed horizontal strip of uniformly-sized, rounded
/// cards just below the title and action buttons.
///
/// `LazyHStack` rather than `HStack` — a well-illustrated paper carries a
/// couple of dozen figures, and only the ones actually scrolled to should
/// be downloaded.
struct FigureCarouselView: View {
    let figures: [Paper.Figure]
    /// The figure being fetched for full-screen display, if any. Tapping
    /// one downloads the whole set (Quick Look needs real files to swipe
    /// between), so the wait belongs on the card that was tapped.
    var preparingID: Paper.Figure.ID?
    var onSelect: (Paper.Figure) -> Void

    /// Sized for a plot rather than a phone screenshot: figures are
    /// overwhelmingly landscape, and a fixed frame keeps the strip from
    /// reflowing as each image arrives at its own size.
    private static let cardSize = CGSize(width: 260, height: 180)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(figures) { figure in
                    Button {
                        onSelect(figure)
                    } label: {
                        card(for: figure)
                    }
                    .buttonStyle(.plain)
                    // Guards against a second tap starting the same
                    // download again. On the buttons rather than the
                    // ScrollView, so the strip still scrolls while a
                    // figure is being fetched.
                    .disabled(preparingID != nil)
                }
            }
            .padding(.horizontal)
        }
    }

    private func card(for figure: Paper.Figure) -> some View {
        AsyncImage(url: figure.imageURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            default:
                ProgressView()
            }
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .padding(8)
        // Plots are line art on a transparent or white background, so they
        // need a light backdrop of their own to stay legible in dark mode
        // — the same thing PDF viewers do. One of the few places a literal
        // color is right instead of a semantic one.
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if preparingID == figure.id {
                ZStack {
                    Color(.systemBackground).opacity(0.7)
                    ProgressView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityLabel(figure.caption ?? figure.label ?? "Figure")
    }
}

#Preview {
    FigureCarouselView(
        figures: [
            Paper.Figure(
                url: "https://inspirehep.net/files/87e9d873f881affa0a5a68c114ea23ca",
                caption: "Evolution of the surface abundances of various chemical species.",
                label: "FIG. 1"
            )
        ],
        onSelect: { _ in }
    )
}
