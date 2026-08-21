import SwiftUI

/// One entry in the New feed, laid out the way a newspaper sets a story:
/// a plot, a kicker, the headline, the byline, and enough of the abstract
/// to decide without opening it.
///
/// No card chrome — no fill, no border, no shadow. What separates one
/// headline from the next is the rules `HeadlineFeedView` draws between
/// them, which is why this view carries only padding.
///
/// **Every headline is exactly the same height.** That keeps the rule
/// under a row of three from stopping at three different distances from
/// the text above it, it settles what to do with a headline that has no
/// plot (the abstract takes the lines the plot would have), and it hands
/// `List` a cell it never has to re-measure — `MathTextView` reports its
/// height asynchronously, seconds late, once KaTeX's fonts load.
struct HeadlineView: View {
    let paper: Paper

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Everything below the plot, at the default text size: the kicker,
    /// three lines of title, a byline, `abstractLines` of abstract, the
    /// footer, the gaps between them, and the view's own padding — about
    /// 300 points of that, rounded up.
    ///
    /// Deliberately generous. Slack is absorbed by the `Spacer` above the
    /// footer and costs nothing, while coming up short clips the footer:
    /// KaTeX line boxes are taller than plain text wherever an abstract
    /// carries a fraction or a subscripted subscript, so six clamped
    /// lines are not always six times the font's line height.
    /// `@ScaledMetric` so the box grows with Dynamic Type rather than
    /// swallowing the text.
    @ScaledMetric(relativeTo: .footnote) private var textBlockHeight: CGFloat = 320

    /// Deep enough to actually read a paragraph, which is the point of
    /// this screen — `PaperRowView` stops at two because a search result
    /// is something you scan past. Six is what the web version of this
    /// feed uses.
    private static let abstractLines = 6

    /// A fixed height rather than an aspect ratio, for the reason
    /// `FigureCarouselView` fixes its card size: plots arrive at every
    /// shape imaginable, and one that resized as each image landed would
    /// reflow the whole column under it. Shorter in a regular width, where
    /// two or three of these sit side by side.
    private var thumbnailHeight: CGFloat {
        horizontalSizeClass == .regular ? 150 : 170
    }

    /// What the plot actually costs the box: the image plus its own inset
    /// and the gap to the kicker below it.
    private var thumbnailBlockHeight: CGFloat {
        thumbnailHeight + 2 * Self.thumbnailInset + Self.spacing
    }

    private var cellHeight: CGFloat { textBlockHeight + thumbnailBlockHeight }

    /// Without a plot, the abstract is given the lines the plot would have
    /// taken — filling the box rather than leaving a hole under a short
    /// story, and keeping every headline the same height either way.
    ///
    /// Rounded *down*, and less a couple of lines' margin. Overshooting
    /// here is the one way this layout can actually break: the extra text
    /// would push the footer past the clip and out of the box, where a
    /// couple of lines of slack merely sit under the abstract.
    private var abstractLineLimit: Int {
        guard paper.headlineFigure == nil else { return Self.abstractLines }
        let lineHeight = UIFont.preferredFont(forTextStyle: .footnote).lineHeight
        let extra = (thumbnailBlockHeight - 2 * lineHeight) / lineHeight
        return Self.abstractLines + max(0, Int(extra))
    }

    private static let spacing: CGFloat = 8
    private static let thumbnailInset: CGFloat = 6

    private var thumbnailShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if let figure = paper.headlineFigure {
                thumbnail(figure)
            }

            if let kicker = paper.kicker {
                KickerText(text: kicker)
            }

            AdaptiveMathText(text: paper.title, textStyle: .headline, weight: .semibold, lineLimit: 3)

            if !paper.authorsSummaryLine.isEmpty {
                Text(paper.authorsSummaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let abstract = paper.abstract, !abstract.isEmpty {
                AdaptiveMathText(text: abstract, textStyle: .footnote, lineLimit: abstractLineLimit)
            }

            // Pins the footer to the bottom of the fixed box, so a short
            // abstract leaves its slack in one place instead of letting
            // the line under the row drift away from the text.
            Spacer(minLength: 0)

            // The date lives in the section header above, so the footer
            // carries what the header can't: where to find it, and how
            // much it has been picked up.
            HStack(spacing: 16) {
                if let arxivID = paper.arxivID {
                    Text("arXiv:\(arxivID)")
                }
                if paper.citationCount > 0 {
                    Label("\(paper.citationCount)", systemImage: "quote.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(.tight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(height: cellHeight, alignment: .top)
        // Dynamic Type at its largest can still overrun the estimate; a
        // clipped last line beats a headline growing into its neighbour.
        .clipped()
        // The whole block is one link, the gaps between the lines
        // included — without this, a tap that lands between the byline
        // and the abstract falls through.
        .contentShape(Rectangle())
        // A headline is a bounded rectangle with rules around it, so it
        // grows into the detail screen the way a card does. Outside the
        // padding, so what expands is the whole block the reader touched.
        .paperTransitionSource(paper)
    }

    private func thumbnail(_ figure: Paper.Figure) -> some View {
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
        .frame(height: thumbnailHeight)
        .frame(maxWidth: .infinity)
        .padding(Self.thumbnailInset)
        // Plots are line art on transparent or white, so they need a light
        // backdrop of their own to survive dark mode — the same literal
        // white `FigureCarouselView` uses, and for the same reason.
        .background(Color.white, in: thumbnailShape)
        .overlay(thumbnailShape.strokeBorder(Color(.separator), lineWidth: 0.5))
        // Captions are full LaTeX and often a paragraph long, so they're
        // read out rather than shown.
        .accessibilityLabel(figure.caption ?? figure.label ?? "Figure")
    }
}

#Preview {
    HeadlineView(paper: .preview)
}
