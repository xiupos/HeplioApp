import SwiftUI

/// The title block at the top of `PaperDetailView`: kicker, title,
/// authors, and the date/citation line. Split out because the author
/// names carry the whole author-navigation interaction, which has more
/// rules to it than the rest of the screen put together.
struct PaperHeaderView: View {
    let paper: Paper

    /// How many author names to show before collapsing, and the point
    /// past which picking one moves from a menu to a pushed, searchable
    /// screen. HEP papers run from single-author to a few thousand, so
    /// both ends have to work.
    static let inlineAuthorLimit = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let kicker = paper.kicker {
                // No line limit: this screen has the width to wrap a long
                // collaboration name where a row or a card doesn't.
                KickerText(text: kicker, lineLimit: nil)
            }

            // Titles/abstracts in this field are essentially always LaTeX,
            // so MathJax renders them directly rather than sniffing for
            // markup first.
            MathTextView(text: paper.title, fontTextStyle: .title, fontWeight: .bold)

            authors

            HStack(spacing: 16) {
                if let formattedDate = paper.formattedDate {
                    Label(formattedDate, systemImage: "calendar")
                }
                if paper.citationCount > 0 {
                    Label("\(paper.citationCount) citations", systemImage: "quote.bubble")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .labelStyle(.tight)
        }
    }

    /// Tapping the names opens whichever author the reader wants. A lone
    /// author goes straight through; a few offer a menu, which anchors
    /// itself to the names rather than floating in from the middle of the
    /// screen the way a `confirmationDialog` popover does. Past
    /// `inlineAuthorLimit` the list is truncated and the choice moves to
    /// a pushed, searchable screen — a menu of a collaboration paper's
    /// few thousand names would be no more usable than a dialog.
    @ViewBuilder
    private var authors: some View {
        if !paper.authors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if paper.authors.count == 1, let author = paper.authors.first {
                    NavigationLink(value: author) {
                        names
                    }
                    .buttonStyle(.plain)
                } else if paper.authors.count <= Self.inlineAuthorLimit {
                    Menu {
                        ForEach(paper.authors) { author in
                            NavigationLink(value: author) {
                                Text(author.fullName)
                            }
                        }
                    } label: {
                        names
                    }
                    // A menu tints its label with the accent color, which
                    // would make this one block of author names orange
                    // while the same names on a one-author or
                    // thousand-author paper stay secondary gray. As a
                    // plain button it keeps the label's own styling.
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: authorListDestination) {
                        names
                    }
                    .buttonStyle(.plain)
                }

                if paper.authors.count > Self.inlineAuthorLimit {
                    NavigationLink(
                        "Show All \(paper.authors.count) Authors",
                        value: authorListDestination
                    )
                    .font(.subheadline)
                }
            }
        }
    }

    private var names: some View {
        let shown = paper.authors.prefix(Self.inlineAuthorLimit)
            .map(\.nameWithAffiliation)
            .joined(separator: "; ")
        return Text(paper.authors.count > Self.inlineAuthorLimit ? "\(shown); …" : shown)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorListDestination: AuthorListDestination {
        AuthorListDestination(paperID: paper.id)
    }
}

#Preview {
    NavigationStack {
        PaperHeaderView(paper: .preview)
            .padding()
    }
}
