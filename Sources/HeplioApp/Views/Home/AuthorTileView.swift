import SwiftUI

/// One person as a grid tile, for Home's "Authors to Follow".
///
/// Wears the same `cardChrome()` as `PaperCardView` and `BrowseTileView`,
/// for the reason recorded there: the screen should read as one thing
/// made of one material, not as three sections that each invented their
/// own. The only difference is what's written on it.
struct AuthorTileView: View {
    let author: Paper.Author

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(author.fullName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            // INSPIRE publishes affiliations already abbreviated — "DESY",
            // "Madrid, IFT" — so the first one is used as given, the same
            // way `PaperHeaderView` uses it.
            if let affiliation = author.affiliations.first {
                Text(affiliation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .cardChrome()
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
        AuthorTileView(author: Paper.preview.authors[0])
    }
    .padding()
    .background(Color(.secondarySystemBackground))
}
