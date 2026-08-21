import SwiftUI

/// The small tinted line above a title — the collaboration, the arXiv
/// category, or the journal, whichever `Paper.kicker` picked. News sets
/// one over every story; four screens here do the same, and this is so
/// they keep agreeing on what it looks like.
///
/// Only the size varies between them: a card's is `.caption2` where a row,
/// a headline and the detail header use `.caption`.
struct KickerText: View {
    let text: String
    var textStyle: Font.TextStyle = .caption
    /// The detail header passes `nil` — it has the width to wrap a long
    /// collaboration name, where a row or a card would be pushed out of
    /// shape by it.
    var lineLimit: Int? = 1

    var body: some View {
        Text(text.uppercased())
            .font(.system(textStyle, weight: .semibold))
            .foregroundStyle(.tint)
            .lineLimit(lineLimit)
    }
}
