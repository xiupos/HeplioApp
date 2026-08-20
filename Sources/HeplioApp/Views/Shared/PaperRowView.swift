import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    /// Bibliography number to show in a leading column, e.g. "[12]" in a
    /// References list. Caller-formatted so this view stays agnostic about
    /// where the number comes from.
    var number: String?
    /// Shows a trailing "opens elsewhere" glyph for rows that link out to
    /// an external site instead of pushing an in-app detail screen.
    var showsExternalLinkIndicator: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let number {
                    Text(number)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let kicker = paper.kicker {
                        Text(kicker.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }

                    AdaptiveMathText(text: paper.title, font: .title3.weight(.semibold), fontTextStyle: .title3, fontWeight: .semibold, lineLimit: 3)

                    if !paper.authorsSummaryLine.isEmpty {
                        Text(paper.authorsSummaryLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let abstract = paper.abstract, !abstract.isEmpty {
                        AdaptiveMathText(text: abstract, font: .footnote, fontTextStyle: .footnote, lineLimit: 2)
                            .foregroundStyle(.primary)
                    } else if !paper.hasInspireRecord, let externalLinkURL = paper.externalLinkURL {
                        // Nothing INSPIRE-side to show — the link this row
                        // will open, so the space doesn't sit empty.
                        Text(externalLinkURL.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 16) {
                        if let formattedDate = paper.formattedDate {
                            Label(formattedDate, systemImage: "calendar")
                        }
                        if paper.citationCount > 0 {
                            Label("\(paper.citationCount)", systemImage: "quote.bubble")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.tight)
                    .padding(.top, 2)
                }
            }

            if showsExternalLinkIndicator {
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    List {
        PaperRowView(paper: .preview)
        PaperRowView(paper: .preview, number: "[12]")
        PaperRowView(paper: .preview, number: "[13]", showsExternalLinkIndicator: true)
    }
}
