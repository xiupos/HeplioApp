import SwiftUI

/// Renders `text` as a plain `Text`, falling back to `MathTextView` only
/// when it actually contains LaTeX/MathML markup — avoids a `WKWebView`
/// per row for the common (math-free) case.
struct AdaptiveMathText: View {
    let text: String
    var font: Font
    var fontTextStyle: Font.TextStyle
    var fontWeight: Font.Weight = .regular
    var lineLimit: Int? = nil

    var body: some View {
        if text.containsMathMarkup {
            MathTextView(text: text, fontTextStyle: fontTextStyle, fontWeight: fontWeight, lineLimit: lineLimit)
        } else {
            Text(text)
                .font(font)
                .lineLimit(lineLimit)
        }
    }
}
