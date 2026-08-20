import Foundation

/// The HTML page `MathTextView` loads into its web view.
///
/// Split out of the view, and `Foundation`-only, for the reason the rest
/// of the project draws that line: **this is the half that can be checked
/// from a Linux dev machine.** Generate it, write it to a file, open it in
/// a real browser, and the typesetting is verifiable without a device —
/// which is how the KaTeX switch was confirmed. Left inside
/// `MathWebView` it could only be verified by copying it, and a copy
/// drifts.
///
/// Everything platform-shaped (the Dynamic Type point size, the colour
/// scheme) is resolved by the view and handed over as a plain value, so
/// this stays a pure function of its inputs.
struct MathDocument {
    let text: String
    /// Already resolved through `UIFont.preferredFont`, so Dynamic Type
    /// is respected without this needing UIKit.
    let fontSize: Double
    var isBold: Bool = false
    var isDark: Bool = false
    /// Caps the rendered text at this many lines (CSS `-webkit-line-clamp`),
    /// like SwiftUI's `.lineLimit()`.
    var lineLimit: Int? = nil

    var html: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script>
        function reportHeight() {
          window.webkit.messageHandlers.sizeHandler.postMessage(document.body.scrollHeight);
        }
        window.addEventListener('load', reportHeight);
        </script>
        \(typesetterHead)
        <style>
          body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font-family: -apple-system, system-ui, sans-serif;
            font-size: \(fontSize)px;
            font-weight: \(isBold ? 600 : 400);
            line-height: 1.4;
            -webkit-text-size-adjust: 100%;
          }
          \(lineClampCSS)
        </style>
        </head>
        <body>
        <div id="content">\(text.mathRenderingHTML)</div>
        </body>
        </html>
        """
    }

    /// Which typesetter this particular string needs. KaTeX is 7.7× lighter
    /// on the wire and synchronous, so it's the default; MathJax is loaded
    /// only for the one input KaTeX can't take.
    private var typesetterHead: String {
        text.containsMathML ? Self.mathJaxHead : kaTeXHead
    }

    private var textColor: String { isDark ? "#EBEBF5" : "#1C1C1E" }

    /// KaTeX's `auto-render` extension, which scans for the same
    /// delimiters MathJax is configured with and typesets them in place.
    ///
    /// `throwOnError: false` paired with `errorColor` set to the body
    /// colour is the load-bearing part: KaTeX supports less of LaTeX than
    /// MathJax does, and INSPIRE abstracts genuinely contain author-defined
    /// macros (`\ord`, `\eps` turned up in a 500-record sample). KaTeX
    /// leaves such a span as its source text, and in the body colour rather
    /// than its default red that degrades to "shows the LaTeX" instead of
    /// "shows an error".
    private var kaTeXHead: String {
        """
        <link rel="stylesheet" href="\(Self.kaTeXBase)/katex.min.css">
        <script defer src="\(Self.kaTeXBase)/katex.min.js"></script>
        <script defer src="\(Self.kaTeXBase)/contrib/auto-render.min.js"></script>
        <script>
        window.addEventListener('DOMContentLoaded', function () {
          renderMathInElement(document.getElementById('content'), {
            delimiters: [
              { left: '$$', right: '$$', display: true },
              { left: '\\\\[', right: '\\\\]', display: true },
              { left: '$', right: '$', display: false },
              { left: '\\\\(', right: '\\\\)', display: false }
            ],
            throwOnError: false,
            errorColor: '\(textColor)',
            strict: false
          });
          // KaTeX lays out with its own web fonts, so the measured height
          // isn't final until they've loaded.
          document.fonts.ready.then(reportHeight);
        });
        </script>
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

    /// Pinned rather than tracking a range: KaTeX has changed rendering
    /// between minor versions, and this is the one thing in the app whose
    /// output is a layout measurement fed back into SwiftUI.
    private static let kaTeXBase = "https://cdn.jsdelivr.net/npm/katex@0.18.4/dist"

    /// Only for text carrying literal MathML — 2.5% of abstracts, and the
    /// one input KaTeX can't take. Measured on the wire at 618,769 bytes
    /// against KaTeX's 80,788, which is why it isn't the default.
    private static let mathJaxHead = """
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
        </script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-svg.js" id="MathJax-script" async></script>
        """
}
