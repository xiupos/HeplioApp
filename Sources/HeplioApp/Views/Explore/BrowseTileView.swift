import SwiftUI

/// One shelf entry as a grid tile. Deliberately the same material as
/// `PaperCardView` — `systemBackground` fill, a hairline `separator`
/// border, the same corner radius and shadow — so the carousel above and
/// the grids below read as one screen made of one thing, and no new
/// design vocabulary is introduced.
///
/// Fixed height, not intrinsic: a row of tiles whose heights depend on
/// whether the subtitle wrapped ("CERN, LHC" vs "T2K to Super-Kamiokande")
/// would sit at ragged heights across the grid.
struct BrowseTileView: View {
    let topic: BrowseTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let subtitle = topic.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        BrowseTileView(topic: .category(.hepPh))
        BrowseTileView(topic: .collaboration("LIGO Scientific"))
        BrowseTileView(topic: .landmarks)
    }
    .padding()
    .background(Color(.secondarySystemBackground))
}
