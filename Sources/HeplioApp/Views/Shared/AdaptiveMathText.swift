import SwiftUI

/// Renders `text` as a plain `Text`, falling back to `MathTextView` only
/// when it actually contains LaTeX/MathML markup — avoids a `WKWebView`
/// per row for the common (math-free) case.
///
/// The plain path still runs `resolvingInlineMarkup`: INSPIRE text that
/// needs no math typesetting can still carry `<sup>` or `<i>`, which a
/// bare `Text` would show as literal angle brackets.
///
/// **This is also where math text stops taking touches.** A `WKWebView`
/// is a real UIKit view: it takes the touch, so a tap landing on typeset
/// text inside a `Button` or `NavigationLink` never reaches it — found on
/// device as "tapping a headline's abstract doesn't open the paper".
/// Every call site here sits inside something tappable and none of the
/// text is itself interactive. `PaperDetailView` deliberately doesn't
/// come through here: it isn't inside a button, and its abstract has to
/// stay selectable so it can be copied or translated.
struct AdaptiveMathText: View {
    let text: String
    /// One text style for both paths. It used to be two parameters — a
    /// `Font` for the `Text` branch and a `Font.TextStyle` for the web
    /// view's Dynamic Type lookup — which every call site had to keep
    /// saying twice and in agreement.
    var textStyle: Font.TextStyle
    var weight: Font.Weight = .regular
    var lineLimit: Int? = nil

    var body: some View {
        if text.containsMathMarkup {
            MathTextView(text: text, fontTextStyle: textStyle, fontWeight: weight, lineLimit: lineLimit)
                .allowsHitTesting(false)
        } else {
            Text(text.resolvingInlineMarkup)
                .font(.system(textStyle, weight: weight))
                .lineLimit(lineLimit)
        }
    }
}
