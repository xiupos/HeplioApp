import Foundation

extension String {
    /// Whether this text contains LaTeX (`$...$`, `\(...\)`, `\[...\]`) or
    /// MathML (`<math>`) markup that needs `MathTextView`'s `WKWebView`.
    var containsMathMarkup: Bool {
        contains("$")
            || contains("\\(")
            || contains("\\[")
            || range(of: "<math", options: [.caseInsensitive]) != nil
    }
}
