import Foundation

/// INSPIRE's titles and abstracts are not plain text. Depending on where a
/// record came from they carry LaTeX, MathML (sometimes namespaced, as
/// `<mml:math>`), presentational HTML (`<sup>`, `<i>`, `<p>`), and JATS
/// wrappers from a publisher's own XML (`<inline-formula>`,
/// `<tex-math notation="LaTeX">$…$</tex-math>`). Measured over 600 live
/// records: TeX in 15.5% of titles and 64% of abstracts, MathML in 0.5%
/// and 2.5%, and the HTML/JATS family in under 2% — rare, but it shows up
/// as raw `<sup>3</sup>` on screen when it isn't handled, which is worse
/// than any of them being missing.
extension String {
    /// Whether this text needs `MathTextView`'s `WKWebView` at all.
    ///
    /// Deliberately **not** true for `<sup>`/`<sub>` alone: those are
    /// resolved to Unicode by `resolvingInlineMarkup`, and a superscript
    /// isn't worth a web view when two thirds of rows already want one for
    /// their abstract.
    var containsMathMarkup: Bool {
        contains("$") || contains("\\(") || contains("\\[") || containsMathML
    }

    /// Whether the text carries literal MathML, which decides *which*
    /// typesetter `MathTextView` loads: KaTeX takes TeX input only, so the
    /// 2.5% of abstracts with a `<math>` element need MathJax.
    var containsMathML: Bool {
        range(of: "<(\\w+:)?math\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Plain text for the non-math path: `<sup>`/`<sub>` become Unicode
    /// where the characters exist, every other tag is dropped.
    ///
    /// Dropping rather than escaping is the right default for this data —
    /// a `<` in an INSPIRE title that forms a well-formed tag is always
    /// markup, never something the author typed.
    var resolvingInlineMarkup: String {
        guard contains("<") else { return self }
        return Self.scriptTagsResolved(in: self).replacingOccurrences(
            of: Self.tagPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// The body HTML handed to `MathTextView`'s web view.
    ///
    /// Three kinds of thing come out of INSPIRE and each needs its own
    /// treatment, which is why this isn't a plain escape:
    ///
    /// - **MathML blocks** pass through as real markup — MathJax's MathML
    ///   processor only typesets actual DOM nodes, not escaped text. Any
    ///   namespace prefix is stripped, since an HTML parser reads
    ///   `<mml:math>` as an element literally named "mml:math" and MathJax
    ///   never finds it.
    /// - **Presentational HTML** (`<sup>`, `<i>`, `<p>`, …) passes through
    ///   too. The web view renders it natively at no MathJax cost, and
    ///   it's what the publisher meant. Attributes are dropped — they're
    ///   noise like `dir="ltr"` or `loc="post"`.
    /// - **Everything else that parses as a tag** is dropped while its
    ///   contents are kept, which is exactly right for JATS wrappers:
    ///   `<tex-math notation="LaTeX">$^{94}$</tex-math>` collapses to
    ///   `$^{94}$`, and MathJax takes it from there.
    ///
    /// Text outside tags is escaped as usual.
    var mathRenderingHTML: String {
        let (masked, mathML) = Self.maskingMathML(in: self)
        var html = Self.escapingOutsideTags(masked)
        for (index, block) in mathML.enumerated() {
            html = html.replacingOccurrences(of: Self.placeholder(index), with: block)
        }
        return html
    }
}

private extension String {
    /// Tags whose meaning survives into the web view. Namespace prefixes
    /// are stripped before the lookup, so `<jats:p>` counts as `<p>`.
    static let passthroughTags: Set<String> = [
        "sup", "sub", "i", "b", "em", "strong", "br", "p", "ul", "ol", "li"
    ]

    /// A well-formed tag: a name, then anything up to the closing angle
    /// bracket, with quoted attribute values allowed to contain one.
    static let tagPattern = "</?[A-Za-z][\\w:.-]*(?:\"[^\"]*\"|'[^']*'|[^>\"'])*>"

    static let mathMLPattern = "<(?:\\w+:)?math\\b(?:\"[^\"]*\"|'[^']*'|[^>\"'])*>[\\s\\S]*?</(?:\\w+:)?math\\s*>"

    /// U+FFFC OBJECT REPLACEMENT CHARACTER — stands in for content held
    /// out of the escaping pass, and won't occur in a paper's own text.
    static func placeholder(_ index: Int) -> String { "\u{FFFC}\(index)\u{FFFC}" }

    /// Walks `pattern`'s matches through `text`, rewriting each match with
    /// `transform` and each stretch of text between them with `between`.
    ///
    /// All three passes in this file are that same splice, and the cursor
    /// arithmetic is exactly where an off-by-one would hide, so it's
    /// written once. A pattern that fails to compile leaves the text
    /// untouched apart from `between` — which for the escaping pass means
    /// the safe outcome, everything escaped and nothing passed through.
    static func rewriting(
        _ text: String,
        matching pattern: String,
        between: (String) -> String = { $0 },
        with transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return between(text)
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return between(text) }

        var result = ""
        var cursor = 0
        for match in matches {
            result += between(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += transform(match, source)
            cursor = match.range.upperBound
        }
        result += between(source.substring(from: cursor))
        return result
    }

    /// Lifts MathML blocks out of the text so escaping can't touch them,
    /// stripping any namespace prefix on the way.
    static func maskingMathML(in text: String) -> (masked: String, blocks: [String]) {
        var blocks: [String] = []
        let masked = rewriting(text, matching: mathMLPattern) { match, source in
            let token = placeholder(blocks.count)
            blocks.append(
                source.substring(with: match.range).replacingOccurrences(
                    of: "(</?)\\w+:",
                    with: "$1",
                    options: .regularExpression
                )
            )
            return token
        }
        return (masked, blocks)
    }

    /// Escapes the text between tags, and rewrites each tag to either its
    /// bare passthrough form or nothing at all.
    static func escapingOutsideTags(_ text: String) -> String {
        rewriting(text, matching: tagPattern, between: escaped) { match, source in
            passthroughForm(of: source.substring(with: match.range))
        }
    }

    static func passthroughForm(of tag: String) -> String {
        let isClosing = tag.hasPrefix("</")
        let name = tagName(of: tag)
        guard passthroughTags.contains(name) else { return "" }
        return isClosing ? "</\(name)>" : "<\(name)>"
    }

    static func tagName(of tag: String) -> String {
        let body = tag.drop { $0 == "<" || $0 == "/" }
        let name = body.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
        // `jats:p` and `mml:mi` mean `p` and `mi`.
        return String(name.split(separator: ":").last ?? "").lowercased()
    }

    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Unicode super/subscripts, for the plain-text path

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
        "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽",
        ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]

    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
        "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍",
        ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "n": "ₙ"
    ]

    /// Replaces `<sup>…</sup>` / `<sub>…</sub>` with Unicode. Content that
    /// has no Unicode form is kept inline rather than dropped — "N3LO"
    /// reads, "N" does not.
    static func scriptTagsResolved(in text: String) -> String {
        var result = text
        for (tag, table) in [("sup", superscripts), ("sub", subscripts)] {
            let pattern = "<(?:\\w+:)?\(tag)\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?\(tag)\\s*>"
            result = rewriting(result, matching: pattern) { match, source in
                String(source.substring(with: match.range(at: 1)).map { table[$0] ?? $0 })
            }
        }
        return result
    }
}
