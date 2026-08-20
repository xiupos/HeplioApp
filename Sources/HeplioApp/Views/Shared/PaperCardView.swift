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
                    Text(kicker.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }

            AdaptiveMathText(text: paper.title, font: .subheadline.weight(.semibold), fontTextStyle: .subheadline, fontWeight: .semibold, lineLimit: 3)

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
        .frame(width: 200, height: 148, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
