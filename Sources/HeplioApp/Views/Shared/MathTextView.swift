import SwiftUI
import WebKit

/// Renders text that may contain inline (`$...$`, `\(...\)`) or display
/// (`$$...$$`, `\[...\]`) LaTeX, or literal MathML (`<math>...</math>`),
/// using MathJax inside a transparent, self-sizing web view — the same
/// approach arXiv.org and inspirehep.net use on their own pages, since
/// SwiftUI/UIKit have no native math typesetting. Used by both
/// `PaperDetailView` and `PaperRowView`, hence its place under `Shared`.
struct MathTextView: View {
    let text: String
    var fontTextStyle: Font.TextStyle = .body
    var fontWeight: Font.Weight = .regular
    /// When set, adds a CSS `-webkit-line-clamp` cap of this many lines,
    /// like SwiftUI's `.lineLimit()` — only lowers the measured height
    /// for content that would otherwise exceed it.
    var lineLimit: Int? = nil

    @State private var height: CGFloat = 20

    var body: some View {
        MathWebView(text: text, fontTextStyle: fontTextStyle, fontWeight: fontWeight, lineLimit: lineLimit, height: $height)
            .frame(height: height)
    }
}

private struct MathWebView: UIViewRepresentable {
    let text: String
    let fontTextStyle: Font.TextStyle
    let fontWeight: Font.Weight
    let lineLimit: Int?
    @Binding var height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "sizeHandler")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        // SwiftUI re-invokes this on unrelated re-renders too, so skip the
        // expensive MathJax reload unless the HTML actually changed.
        let html = html
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    private var html: String {
        let uiFont = UIFont.preferredFont(forTextStyle: fontTextStyle.uiTextStyle)
        let textColor = colorScheme == .dark ? "#EBEBF5" : "#1C1C1E"
        let weight = fontWeight == .semibold || fontWeight == .bold ? "600" : "400"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script>
        window.MathJax = {
          tex: {
            inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
            displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
          },
          svg: { fontCache: 'global' },
          startup: {
            ready: function () {
              MathJax.startup.defaultReady();
              MathJax.startup.promise.then(reportHeight);
            }
          }
        };
        function reportHeight() {
          window.webkit.messageHandlers.sizeHandler.postMessage(document.body.scrollHeight);
        }
        window.addEventListener('load', reportHeight);
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-svg.js" id="MathJax-script" async></script>
        <style>
          body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font-family: -apple-system, system-ui, sans-serif;
            font-size: \(uiFont.pointSize)px;
            font-weight: \(weight);
            line-height: 1.4;
            -webkit-text-size-adjust: 100%;
          }
          \(lineClampCSS)
        </style>
        </head>
        <body>
        <div id="content">\(Self.htmlEscaped(text))</div>
        </body>
        </html>
        """
    }

    private var lineClampCSS: String {
        guard let lineLimit else { return "" }
        return """
        #content {
          display: -webkit-box;
          -webkit-line-clamp: \(lineLimit);
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        """
    }

    /// HTML-escapes the text, then un-escapes `<math>...</math>` spans back
    /// into real markup — MathJax's MathML processor only typesets actual
    /// DOM elements, not escaped text.
    private static func htmlEscaped(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return unescapeMathMLBlocks(in: escaped)
    }

    private static func unescapeMathMLBlocks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "&lt;math\\b[\\s\\S]*?&lt;/math&gt;",
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let block = nsText.substring(with: match.range)
            let unescapedBlock = block
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: unescapedBlock)
            }
        }
        return result
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var lastLoadedHTML: String?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let newHeight = CGFloat(number.doubleValue)
            DispatchQueue.main.async {
                self.height.wrappedValue = max(newHeight, 20)
            }
        }
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        default: return .body
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MathTextView(text: "A search for $H\\to\\gamma\\gamma$ and $H\\to ZZ^{\\star}\\to 4\\ell$ decays.")
        MathTextView(text: "Using \\(x^2 + y^2 = z^2\\) as the base relation.")
        MathTextView(text: "MathML sample: <math><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></math>")
    }
    .padding()
}
