import SwiftUI
import WebKit

/// Renders text that may contain inline (`$...$`, `\(...\)`) or display
/// (`$$...$$`, `\[...\]`) LaTeX, or literal MathML (`<math>...</math>`),
/// inside a transparent, self-sizing web view — the same approach
/// arXiv.org and inspirehep.net use on their own pages, since SwiftUI and
/// UIKit have no native math typesetting. Used by both `PaperDetailView`
/// and `PaperRowView`, hence its place under `Shared`.
///
/// **What's left here is web-view plumbing only.** The page itself is
/// `MathDocument`, and turning INSPIRE's markup into its body is
/// `String.mathRenderingHTML` — both `Foundation`-only, and deliberately
/// so: they're the parts that can be exercised against live records, and
/// rendered in a real browser, from a Linux dev machine.
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
        // expensive reload — fetching and running a typesetter — unless the
        // page actually changed.
        let html = document.html
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    /// Resolves everything platform-shaped — Dynamic Type, the colour
    /// scheme — so `MathDocument` can stay a pure function of plain values.
    private var document: MathDocument {
        MathDocument(
            text: text,
            fontSize: UIFont.preferredFont(forTextStyle: fontTextStyle.uiTextStyle).pointSize,
            isBold: fontWeight == .semibold || fontWeight == .bold,
            isDark: colorScheme == .dark,
            lineLimit: lineLimit
        )
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
        MathTextView(text: "The virtual N<sup loc=\"post\">3</sup>LO contribution to $gg\\to H$")
        MathTextView(text: "<inline-formula><tex-math notation=\"LaTeX\">$^{94}$</tex-math></inline-formula>Zr from a publisher's JATS")
    }
    .padding()
}
