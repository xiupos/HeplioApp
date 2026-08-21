import SwiftUI

/// Compact, abstract-less card for horizontal carousels — the "More By
/// This Artist" / "You Might Also Like" treatment from Music/News, used
/// where `PaperRowView`'s full row is too tall to lay out side by side.
struct PaperCardView: View {
    let paper: Paper
    /// Bibliography number, e.g. "[12]" in a References carousel.
    var number: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let number {
                    Text(number)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let kicker = paper.kicker {
                    KickerText(text: kicker, textStyle: .caption2)
                }
            }

            AdaptiveMathText(text: paper.title, textStyle: .subheadline, weight: .semibold, lineLimit: 3)

            if !paper.authorsSummaryLine.isEmpty {
                Text(paper.authorsSummaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let formattedDate = paper.formattedDate {
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if !paper.hasInspireRecord, let externalLinkURL = paper.externalLinkURL {
                // Nothing INSPIRE-side to show — the link this card will
                // open, so the space doesn't sit empty.
                Text(externalLinkURL.host ?? externalLinkURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        // `minHeight`, not `height` — at large Dynamic Type sizes the
        // three-line title and the author line both grow, and a fixed
        // height would clip or overflow into the next card. A fixed
        // *width* is fine: these sit in a horizontal scroll, not a grid
        // that needs matched heights.
        .frame(width: 200, alignment: .topLeading)
        .frame(minHeight: 148, alignment: .topLeading)
        .cardChrome()
        // Outside the card's own chrome, so the shape that grows into the
        // detail screen is the rounded card the reader tapped. Cards
        // zoom; `PaperRowView` deliberately doesn't — see
        // `paperTransitionSource`.
        .paperTransitionSource(paper)
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            PaperCardView(paper: .preview, number: "[1]")
            PaperCardView(paper: .preview, number: "[2]")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
