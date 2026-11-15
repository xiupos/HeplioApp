// Heplio's rules (heplio-gtk's SPEC.md): queries and the links typed, INSPIRE's requests, the records
// a search gives, short names, counts, plain text, and the saved queries. Foundation only, no
// networking, so that it builds and is tested on Linux: the tests are at the end, and run
// cases.json, heplio-gtk's examples

import Foundation

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Queries

/// Papers a page of a list has
let pageSize = 25
/// INSPIRE gives no result past the 10,000th
let maxResults = 10_000
let api = "https://inspirehep.net/api/literature"
let listFields = "control_number,titles.title,first_author.full_name,author_count,collaborations.value,"
    + "earliest_date,abstracts.value,arxiv_eprints.value,texkeys,citation_count"
let paperFields = "control_number,titles.title,authors.full_name,authors.ids,authors.affiliations.value,"
    + "collaborations.value,earliest_date,abstracts.value,arxiv_eprints,dois.value,texkeys,citation_count,"
    + "citation_count_without_self_citations,publication_info,number_of_pages,references.record,"
    + "document_type,keywords,report_numbers.value"
let searchTips = URL(string: "https://help.inspirehep.net/knowledge-base/inspire-paper-search/")!

/// INSPIRE's orders, by their `sort` value, and their names
let sorts = [("mostrecent", "Most Recent"), ("mostcited", "Most Cited"), ("bestmatch", "Best Match")]

func sortName(_ sort: String) -> String {
    sorts.first { $0.0 == sort }?.1 ?? sort
}

/// What a list shows: INSPIRE's answer to `q`, in the order `sort`
struct Query: Hashable, Codable, Sendable {
    var q: String
    var sort: String

    /// The list on INSPIRE's site
    var url: URL { URL(string: "https://inspirehep.net/search?p=\(percentEncoded(q))&sort=\(percentEncoded(sort))")! }
}

/// The saved queries at first: the week's hep-th, cross-lists too
let firstSaved = [Query(q: "arxiv_eprints.categories:hep-th and de > today - 7", sort: "mostrecent")]

/// What is typed into the search, as INSPIRE's query: `recid:N` for an INSPIRE link, `arxiv:<id>`
/// for an arXiv link, `doi:<doi>` for a doi.org link. Anything else as it is, trimmed
func inspireQuery(_ typed: String) -> String {
    let typed = typed.trimmed
    func after(_ prefix: String) -> String? {
        guard let r = typed.range(of: prefix) else { return nil }
        var rest = typed[r.upperBound...]
        if let end = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<end] }
        var s = String(rest)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".pdf") { s.removeLast(4) }
        return s
    }
    if let recid = after("inspirehep.net/literature/") { return "recid:\(recid)" }
    if let arxiv = after("arxiv.org/abs/") ?? after("arxiv.org/pdf/") { return "arxiv:\(arxiv)" }
    if let doi = after("doi.org/") { return "doi:\(doi)" }
    return typed
}

/// Saves the query, at the end, or removes it, and every copy of it, if it is saved
func toggled(_ saved: [Query], _ query: Query) -> [Query] {
    saved.contains(query) ? saved.filter { $0 != query } : saved + [query]
}

// MARK: - Requests

/// A page of a list, from 1
func listURL(_ query: Query, page: Int) -> URL {
    let (q, sort) = (percentEncoded(query.q.trimmed), percentEncoded(query.sort))
    return URL(string: "\(api)?q=\(q)&sort=\(sort)&size=\(pageSize)&page=\(page)&fields=\(percentEncoded(listFields))")!
}

/// A page of a list, as INSPIRE's BibTeX: heplio's command's
func listBibtexURL(_ query: Query, page: Int) -> URL {
    let (q, sort) = (percentEncoded(query.q.trimmed), percentEncoded(query.sort))
    return URL(string: "\(api)?q=\(q)&sort=\(sort)&size=\(pageSize)&page=\(page)&format=bibtex")!
}

/// A paper, with all its page shows: `/api/literature/N` ignores `fields`
func paperURL(_ recid: Int) -> URL {
    URL(string: "\(api)?q=\(percentEncoded("recid:\(recid)"))&size=1&fields=\(percentEncoded(paperFields))")!
}

func bibtexURL(_ recid: Int) -> URL {
    URL(string: "\(api)/\(recid)?format=bibtex")!
}

func pdfURL(_ arxiv: String) -> URL {
    URL(string: "https://arxiv.org/pdf/\(arxiv)")!
}

/// The name of a paper's PDF: `hep-th/9711200` → `hep-th-9711200.pdf`
func pdfName(_ arxiv: String) -> String {
    arxiv.replacingOccurrences(of: "/", with: "-") + ".pdf"
}

/// Whether there is a page after `page`, of a list of `total`
func hasMore(total: Int, page: Int) -> Bool {
    page * pageSize < min(total, maxResults)
}

/// INSPIRE's BibTeX, an entry each: each starts on a line that starts with `@`
func bibtexEntries(_ text: String) -> [String] {
    var entries: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("@") {
            entries.append(String(line))
        } else if !entries.isEmpty {
            entries[entries.count - 1] += "\n" + line
        }
    }
    return entries.map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
}

/// Percent-encodes all but the unreserved characters, `+` too, which INSPIRE reads as a space
func percentEncoded(_ s: String) -> String {
    s.utf8.map { b -> String in
        switch b {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"),
             UInt8(ascii: "~"):
            String(UnicodeScalar(b))
        default:
            String(format: "%%%02X", b)
        }
    }.joined()
}

// MARK: - Records

struct Author: Hashable, Sendable {
    var fullName: String
    var bai: String?
    var affiliations: [String] = []

    /// The author's papers: by the author's INSPIRE BAI, else by the name
    var query: String { bai.map { "a \($0)" } ?? "a \"\(fullName)\"" }
}

/// A paper as a search gives it. A list's has only its first author, and no details
struct Record: Hashable, Sendable {
    var recid: Int
    /// As INSPIRE has it, with its TeX
    var title = ""
    var authors: [Author] = []
    var authorCount = 0
    var collaborations: [String] = []
    /// `1997`, `1997-11`, or `1997-11-27`
    var date: String?
    var abstract: String?
    var arxiv: String?
    var categories: [String] = []
    var dois: [String] = []
    var texkey: String?
    var citations: Int?
    var citationsWithoutSelf: Int?
    /// The journals it is in, the publication first
    var journals: [String] = []
    var pages: Int?
    /// The references that are INSPIRE's records; none without `references`
    var references: Int?
    var documentTypes: [String] = []
    /// INSPIRE's own keywords
    var keywords: [String] = []
    var reportNumbers: [String] = []

    /// A hit, `{"metadata": {…}}`; none without `control_number`
    init?(hit: Any) {
        guard let m = (hit as? [String: Any])?["metadata"] as? [String: Any],
              let recid = m["control_number"] as? Int else { return nil }
        self.recid = recid
        func list(_ key: String) -> [[String: Any]] { m[key] as? [[String: Any]] ?? [] }
        func values(_ key: String) -> [String] { list(key).compactMap { $0["value"] as? String } }
        title = list("titles").first?["title"] as? String ?? ""
        func author(_ a: [String: Any]) -> Author? {
            guard let name = a["full_name"] as? String else { return nil }
            let ids = a["ids"] as? [[String: Any]] ?? []
            let bai = ids.first { $0["schema"] as? String == "INSPIRE BAI" }?["value"] as? String
            let affiliations = (a["affiliations"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
            return Author(fullName: name, bai: bai, affiliations: affiliations)
        }
        if let all = m["authors"] as? [[String: Any]] {
            authors = all.compactMap(author)
        } else if let first = m["first_author"] as? [String: Any] {
            authors = author(first).map { [$0] } ?? []
        }
        authorCount = m["author_count"] as? Int ?? authors.count
        collaborations = values("collaborations")
        date = m["earliest_date"] as? String
        abstract = list("abstracts").first?["value"] as? String
        let eprint = list("arxiv_eprints").first
        arxiv = eprint?["value"] as? String
        categories = eprint?["categories"] as? [String] ?? []
        dois = values("dois")
        texkey = (m["texkeys"] as? [String])?.first
        citations = m["citation_count"] as? Int
        citationsWithoutSelf = m["citation_count_without_self_citations"] as? Int
        let info = list("publication_info")
        let published = info.filter { ($0["material"] as? String).map { $0 == "publication" } ?? true }
        let other = info.filter { ($0["material"] as? String).map { $0 != "publication" } ?? false }
        journals = (published + other).compactMap(journal)
        pages = m["number_of_pages"] as? Int
        references = (m["references"] as? [[String: Any]]).map { $0.filter { $0["record"] != nil }.count }
        documentTypes = m["document_type"] as? [String] ?? []
        keywords = list("keywords").filter { $0["schema"] as? String == "INSPIRE" }.compactMap { $0["value"] as? String }
        reportNumbers = values("report_numbers")
    }

    /// `ATLAS Collaboration`, or the first author's short name, with ` et al.` if there are more
    var byline: String {
        if let c = collaborations.first { return c.hasSuffix("Collaboration") ? c : "\(c) Collaboration" }
        let first = authors.first.map { shortName($0.fullName) } ?? ""
        return authorCount > 1 ? "\(first) et al." : first
    }

    /// The paper on INSPIRE's site
    var url: URL { URL(string: "https://inspirehep.net/literature/\(recid)")! }
    var arxivURL: URL? { arxiv.flatMap { URL(string: "https://arxiv.org/abs/\($0)") } }
    /// The papers it cites, and that cite it, as INSPIRE's queries
    var referencesQuery: String { "citedby:recid:\(recid)" }
    var citationsQuery: String { "refersto:recid:\(recid)" }
}

/// A search's `hits.total`, and its records
func parseSearch(_ data: Data) -> (total: Int, records: [Record])? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hits = json["hits"] as? [String: Any], let total = hits["total"] as? Int else { return nil }
    return (total, (hits["hits"] as? [Any] ?? []).compactMap { Record(hit: $0) })
}

/// A field INSPIRE gives as a string or as a number, if it is not blank
private func text(_ value: Any?) -> String? {
    if let s = value as? String { return s.trimmed.isEmpty ? nil : s.trimmed }
    if let n = value as? Int { return String(n) }
    return nil
}

/// The journal, as `Title Volume (Year) Page`, with `(material)` after it unless that is `publication`
private func journal(_ p: [String: Any]) -> String? {
    guard let title = text(p["journal_title"]) else { return nil }
    let material = (p["material"] as? String).flatMap { $0 == "publication" ? nil : "(\($0))" }
    let parts = [title, text(p["journal_volume"]), text(p["year"]).map { "(\($0))" },
                 text(p["artid"]) ?? text(p["page_start"]), material]
    return parts.compactMap { $0 }.joined(separator: " ")
}

/// `Maldacena, Juan Martin` → `J.M. Maldacena`; `He, Zhi-Guo` → `Z.-G. He`. A name without a comma
/// is kept as it is
func shortName(_ full: String) -> String {
    guard let comma = full.firstIndex(of: ",") else { return full.trimmed }
    let last = full[..<comma].trimmed
    let initials = full[full.index(after: comma)...].split(whereSeparator: \.isWhitespace).map { word in
        word.split(separator: "-").compactMap { $0.first.map { "\($0)." } }.joined(separator: "-")
    }.joined()
    return initials.isEmpty ? last : "\(initials) \(last)"
}

/// `1234567` → `1,234,567`
func count(_ n: Int) -> String {
    let digits = Array(String(n))
    var out = ""
    for (i, c) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(c)
    }
    return out
}

/// `1 citation`, `22,814 citations`
func counted(_ n: Int, _ one: String) -> String {
    n == 1 ? "1 \(one)" : "\(count(n)) \(one)s"
}

// MARK: - Plain text

/// TeX, with some HTML, as plain text: `$H\to\gamma\gamma$` → `H→γγ`. INSPIRE's text is not quite
/// TeX: its HTML is undone first; a bare `%`, `&`, or `#` is text, and an odd `$` a dollar
func plain(_ text: String) -> String {
    var parser = TeX(entities(untagged(text)))
    let out = parser.convert(math: false, closing: nil)
    return out.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// HTML's tags as TeX: `<sup>` a superscript, `<sub>` and `<inf>` a subscript, others a space. A
/// `<` that starts no tag is kept
private func untagged(_ text: String) -> String {
    var out = ""
    var rest = Substring(text)
    while let start = rest.firstIndex(of: "<") {
        out += rest[..<start]
        let tag = rest[rest.index(after: start)...]
        guard let first = tag.first, first.isASCII && (first.isLetter || first == "/"),
              let end = tag.firstIndex(of: ">") else {
            out += "<"
            rest = tag
            continue
        }
        let closing = first == "/"
        let name = tag[..<end].drop { $0 == "/" }.prefix { $0.isLetter }.lowercased()
        switch (name, closing) {
        case ("sup", false): out += "$^{"
        case ("sub", false), ("inf", false): out += "$_{"
        case ("sup", true), ("sub", true), ("inf", true): out += "}$"
        default: out += " "
        }
        rest = tag[tag.index(after: end)...]
    }
    return out + rest
}

/// HTML's entities as characters: `&lt;` → `<`, `&#233;` → `é`
private func entities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
    var out = ""
    var rest = Substring(text)
    while let amp = rest.firstIndex(of: "&") {
        out += rest[..<amp]
        let after = rest[rest.index(after: amp)...]
        if let semi = after.prefix(10).firstIndex(of: ";") {
            let name = String(after[..<semi])
            let number = name.hasPrefix("#x") ? Int(name.dropFirst(2), radix: 16)
                : name.hasPrefix("#") ? Int(name.dropFirst()) : nil
            if let c = named[name] ?? number.flatMap(UnicodeScalar.init).map({ String(Character($0)) }) {
                out += c
                rest = after[after.index(after: semi)...]
                continue
            }
        }
        out += "&"
        rest = after
    }
    return out + rest
}

/// A small converter of TeX to text, refdir-ios's: commands become their symbols, scripts become Unicode
/// superscripts and subscripts where there are some, and accents become combining marks
private struct TeX {
    let s: [Character]
    var i = 0
    /// The indices of the `$` that open or close math. An odd one is a dollar
    let toggles: Set<Int>

    init(_ text: String) {
        let chars = Array(text)
        s = chars
        var dollars = chars.indices.filter { chars[$0] == "$" && !TeX.escaped(chars, $0) }
        if dollars.count % 2 == 1 { dollars.removeLast() }
        toggles = Set(dollars)
    }

    /// Whether the character at `i` follows an odd number of backslashes
    private static func escaped(_ s: [Character], _ i: Int) -> Bool {
        var n = 0
        var j = i - 1
        while j >= 0 && s[j] == "\\" { n += 1; j -= 1 }
        return n % 2 == 1
    }

    var atEnd: Bool { i >= s.count }

    /// Converts until `closing` (a `}`), or the end. A `$` toggles math
    mutating func convert(math startMath: Bool, closing: Character?) -> String {
        var math = startMath
        var out = ""
        while !atEnd {
            let c = s[i]
            if c == closing { i += 1; return out }
            if c == "$" && toggles.contains(i) {
                i += 1
                math.toggle()
                continue
            }
            switch c {
            case "\\": out += command(math: math)
            case "{":
                i += 1
                out += convert(math: math, closing: "}")
            case "}": i += 1
            case "^" where math, "_" where math:
                i += 1
                out += script(argument(math: true), up: c == "^")
            case "'" where math:
                i += 1
                out += "′"
            case "~" where math:
                i += 1
                out += " "
            case _ where math && c.isWhitespace:
                i += 1
            case "-" where !math && peek("---"):
                i += 3
                out += "—"
            case "-" where !math && peek("--"):
                i += 2
                out += "–"
            case "`" where !math && peek("``"):
                i += 2
                out += "“"
            case "'" where !math && peek("''"):
                i += 2
                out += "”"
            // Quotes, as TeX sets them
            case "'" where !math:
                i += 1
                out += "’"
            case "`" where !math:
                i += 1
                out += "‘"
            default:
                i += 1
                out.append(c)
            }
        }
        return out
    }

    private func peek(_ text: String) -> Bool {
        let t = Array(text)
        return i + t.count <= s.count && Array(s[i..<i + t.count]) == t
    }

    private mutating func skipSpaces() {
        while !atEnd && s[i].isWhitespace && s[i] != "\n" { i += 1 }
    }

    /// One argument: a group, a command, or a character
    private mutating func argument(math: Bool) -> String {
        skipSpaces()
        guard !atEnd else { return "" }
        switch s[i] {
        case "{":
            i += 1
            return convert(math: math, closing: "}")
        case "\\":
            return command(math: math)
        case "$" where toggles.contains(i), "}":
            return ""
        default:
            i += 1
            return String(s[i - 1])
        }
    }

    /// Skips an optional argument in brackets
    private mutating func skipOptional() {
        skipSpaces()
        guard !atEnd, s[i] == "[", let end = s[i...].firstIndex(of: "]") else { return }
        i = end + 1
    }

    /// The command at `i`, a backslash
    private mutating func command(math: Bool) -> String {
        i += 1
        guard !atEnd else { return "" }
        let first = s[i]
        guard first.isASCII && first.isLetter else {
            i += 1
            if let accent = TeX.accents[String(first)] { return accented(argument(math: math), accent) }
            switch first {
            case ",", ";", ":", " ", "\n", "\\": return " "
            case "!", "/", "-": return ""
            default: return String(first)
            }
        }
        var name = ""
        while !atEnd && s[i].isASCII && s[i].isLetter {
            name.append(s[i])
            i += 1
        }
        // TeX ends a command's name with the spaces after it
        skipSpaces()
        if let symbol = TeX.symbols[name] { return symbol }
        if let accent = TeX.accents[name] { return accented(argument(math: math), accent) }
        switch name {
        case "text", "textrm", "textit", "textbf", "textsf", "texttt", "textup", "textnormal", "textsc",
             "emph", "mbox", "hbox", "url":
            return argument(math: false)
        case "mathrm", "mathit", "mathbf", "mathsf", "mathtt", "mathcal", "mathscr", "mathfrak", "boldsymbol",
             "bm", "operatorname", "ensuremath":
            // Upright letters: the font is not kept
            return argument(math: math)
        case "mathbb":
            let letters: [Character: String] = ["R": "ℝ", "C": "ℂ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "P": "ℙ"]
            return argument(math: math).map { letters[$0] ?? String($0) }.joined()
        case "frac", "dfrac", "tfrac":
            let (a, b) = (argument(math: true), argument(math: true))
            return "\(grouped(a))/\(grouped(b))"
        case "sqrt":
            skipOptional()
            return "√" + grouped(argument(math: true))
        case "not":
            return argument(math: math) + "\u{338}"
        case "left", "right", "bigl", "bigr", "Bigl", "Bigr", "big", "Big", "bigg", "Bigg", "middle":
            skipSpaces()
            if !atEnd && s[i] == "." { i += 1 }
            return ""
        case "cite", "ref", "label", "eqref", "footnote", "vspace", "hspace":
            _ = argument(math: math)
            return ""
        case "quad", "qquad", "space", "enspace", "thinspace", "medspace", "thickspace":
            return " "
        default:
            // Unknown: dropped, and its argument, if it has one, read as text
            return ""
        }
    }

    /// `a+b` → `(a+b)`, for a fraction or a root
    private func grouped(_ text: String) -> String {
        text.count > 1 && text.contains(where: { "+-−=/ ".contains($0) }) ? "(\(text))" : text
    }

    private func accented(_ text: String, _ mark: String) -> String {
        text.map { String($0) + mark }.joined()
    }

    /// `x` as a superscript or subscript: in Unicode if every character has one, else after `^` or
    /// `_`, in parentheses if it is longer than a character
    private func script(_ text: String, up: Bool) -> String {
        let text = text.trimmed
        if text.isEmpty { return "" }
        if up && ["′", "*", "∗", "†", "‡", "°", "∘"].contains(text) { return text == "∘" ? "°" : text }
        let table = up ? TeX.superscripts : TeX.subscripts
        let mapped = text.compactMap { table[$0] }
        if mapped.count == text.count { return String(mapped) }
        return (up ? "^" : "_") + (text.count > 1 ? "(\(text))" : text)
    }

    static let superscripts: [Character: Character] = {
        var t: [Character: Character] = [:]
        for (a, b) in zip("0123456789+-−=()niabcdefghijklmoprstuvwxyzABDEGHIJKLMNOPRTUVWαβγδεθιφχ",
                          "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁻⁼⁽⁾ⁿⁱᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂᵅᵝᵞᵟᵋᶿᶥᵠᵡ") {
            t[a] = b
        }
        return t
    }()

    static let subscripts: [Character: Character] = {
        var t: [Character: Character] = [:]
        for (a, b) in zip("0123456789+-−=()aehijklmnoprstuvxβγρφχ", "₀₁₂₃₄₅₆₇₈₉₊₋₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵦᵧᵨᵩᵪ") {
            t[a] = b
        }
        return t
    }()

    /// Combining marks, by command
    static let accents: [String: String] = [
        "bar": "\u{305}", "overline": "\u{305}", "tilde": "\u{303}", "widetilde": "\u{303}", "hat": "\u{302}",
        "widehat": "\u{302}", "vec": "\u{20D7}", "dot": "\u{307}", "ddot": "\u{308}", "check": "\u{30C}",
        "breve": "\u{306}", "acute": "\u{301}", "grave": "\u{300}",
        "'": "\u{301}", "`": "\u{300}", "^": "\u{302}", "\"": "\u{308}", "~": "\u{303}", "=": "\u{304}",
        ".": "\u{307}", "u": "\u{306}", "v": "\u{30C}", "H": "\u{30B}", "c": "\u{327}", "r": "\u{30A}",
        "k": "\u{328}",
    ]

    static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
        "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ",
        "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "longrightarrow": "⟶",
        "longleftarrow": "⟵", "Longrightarrow": "⟹", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "rightleftharpoons": "⇌", "iff": "⟺", "implies": "⟹",
        // Relations
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ll": "≪", "gg": "≫", "ne": "≠", "neq": "≠",
        "sim": "∼", "simeq": "≃", "approx": "≈", "cong": "≅", "equiv": "≡", "propto": "∝", "lesssim": "≲",
        "gtrsim": "≳", "lapprox": "≲", "gapprox": "≳", "in": "∈", "notin": "∉", "ni": "∋",
        "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "perp": "⊥", "parallel": "∥",
        "mid": "|", "vdash": "⊢", "models": "⊨", "prec": "≺", "succ": "≻",
        // Operators
        "times": "×", "pm": "±", "mp": "∓", "cdot": "·", "div": "÷", "ast": "∗", "star": "⋆",
        "circ": "∘", "bullet": "•", "otimes": "⊗", "oplus": "⊕", "ominus": "⊖", "odot": "⊙", "wedge": "∧",
        "land": "∧", "vee": "∨", "lor": "∨", "cup": "∪", "cap": "∩", "setminus": "∖", "dagger": "†",
        "ddagger": "‡", "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭",
        "oint": "∮", "bigcup": "⋃", "bigcap": "⋂", "bigoplus": "⨁", "bigotimes": "⨂", "neg": "¬",
        "lnot": "¬", "forall": "∀", "exists": "∃", "nabla": "∇", "partial": "∂", "Box": "□", "square": "□",
        "triangle": "△", "wr": "≀", "rtimes": "⋊", "ltimes": "⋉",
        // Letters and other symbols
        "infty": "∞", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "emptyset": "∅",
        "varnothing": "∅", "prime": "′", "degree": "°", "angle": "∠", "ldots": "…", "dots": "…",
        "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "langle": "⟨", "rangle": "⟩", "lfloor": "⌊",
        "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|", "Vert": "‖", "lbrace": "{", "rbrace": "}",
        "backslash": "∖", "S": "§", "P": "¶", "copyright": "©", "dag": "†", "ddag": "‡",
        "i": "ı", "j": "ȷ", "o": "ø", "O": "Ø", "ss": "ß", "ae": "æ", "AE": "Æ", "oe": "œ", "OE": "Œ",
        "aa": "å", "AA": "Å", "l": "ł", "L": "Ł", "textendash": "–", "textemdash": "—",
        "textasciitilde": "~", "textasciicircum": "^", "textbackslash": "\\", "texttimes": "×", "textpm": "±",
        "textless": "<", "textgreater": ">", "textunderscore": "_", "textbar": "|", "textellipsis": "…",
        "textquoteleft": "‘", "textquoteright": "’", "textquotedblleft": "“", "textquotedblright": "”",
        "textdegree": "°", "textmu": "µ", "textperthousand": "‰", "LaTeX": "LaTeX",
        "TeX": "TeX",
        // Functions, upright
        "sin": "sin", "cos": "cos", "tan": "tan", "cot": "cot", "sec": "sec", "csc": "csc", "arcsin": "arcsin",
        "arccos": "arccos", "arctan": "arctan", "sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "exp": "exp",
        "log": "log", "ln": "ln", "lg": "lg", "det": "det", "dim": "dim", "ker": "ker", "deg": "deg",
        "arg": "arg", "max": "max", "min": "min", "sup": "sup", "inf": "inf", "lim": "lim", "limsup": "lim sup",
        "liminf": "lim inf", "Pr": "Pr", "gcd": "gcd", "hom": "hom", "Tr": "Tr", "tr": "tr",
        // Spacing and sizing, dropped
        "displaystyle": "", "textstyle": "", "scriptstyle": "", "scriptscriptstyle": "", "limits": "",
        "nolimits": "", "small": "", "large": "", "Large": "", "huge": "", "normalsize": "", "footnotesize": "",
        "scriptsize": "", "tiny": "", "noindent": "", "nonumber": "", "relax": "", "protect": "", "it": "",
        "rm": "", "bf": "", "sf": "", "tt": "", "em": "", "cal": "", "sc": "", "bigskip": " ", "medskip": " ",
        "smallskip": " ", "newline": " ", "par": " ", "cr": " ", "hfill": " ", "nobreak": "",
    ]
}


// MARK: - Tests

// Linux only: the app never builds this. Run with
//   swiftc -parse-as-library Sources/Core.swift -o /tmp/heplio-ios-test && /tmp/heplio-ios-test
// It runs cases.json of this project, or the file whose path it is given, such as heplio-gtk's
// tests/cases.json, to check that this copy is current
#if os(Linux)
@main
enum Tests {
    static var failures = 0
    static var checks = 0

    static func check(_ ok: Bool, _ message: @autoclosure () -> String) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL:", message())
        }
    }

    static func main() {
        let path = CommandLine.arguments.dropFirst().first
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("cases.json").path
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let cases = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        func section(_ name: String) -> [Any] {
            guard let s = cases[name] as? [Any] else { fatalError("no section \(name)") }
            return s
        }
        func query(_ v: Any) -> Query {
            let a = v as! [Any]
            return Query(q: a[0] as! String, sort: a[1] as! String)
        }
        for case let c as [String] in section("query") {
            check(inspireQuery(c[0]) == c[1], "query \(c): \(inspireQuery(c[0]))")
        }
        for case let c as [String: Any] in section("urls") {
            let url: URL
            if let l = c["list"] as? [Any] {
                url = listURL(query(l), page: l[2] as! Int)
            } else if let l = c["list_bibtex"] as? [Any] {
                url = listBibtexURL(query(l), page: l[2] as! Int)
            } else if let recid = c["paper"] as? Int {
                url = paperURL(recid)
            } else if let recid = c["bibtex"] as? Int {
                url = bibtexURL(recid)
            } else if let arxiv = c["pdf"] as? String {
                url = pdfURL(arxiv)
            } else {
                url = query(c["site"]!).url
            }
            check(url.absoluteString == c["expect"] as! String, "url \(c["about"]!): \(url)")
        }
        for case let c as [String: Any] in section("paging") {
            let more = hasMore(total: c["total"] as! Int, page: c["page"] as! Int)
            check(more == c["more"] as! Bool, "paging \(c)")
        }
        for case let c as [String] in section("short_names") {
            check(shortName(c[0]) == c[1], "short name \(c): \(shortName(c[0]))")
        }
        for case let c as [Any] in section("counts") {
            check(count(c[0] as! Int) == c[1] as! String, "count \(c)")
        }
        for case let c as [Any] in section("pdf_names") {
            check(pdfName(c[0] as! String) == c[1] as! String, "pdf name \(c)")
        }
        for case let c as [String: Any] in section("bibtex_entries") {
            let found = bibtexEntries(c["text"] as! String)
            check(found == c["expect"] as! [String], "bibtex entries \(c["about"]!): \(found)")
        }
        for case let c as [String: Any] in section("records") {
            records(c)
        }
        for case let c as [String: Any] in section("toggle") {
            let saved = (c["saved"] as! [Any]).map(query)
            let expect = (c["expect"] as! [Any]).map(query)
            check(toggled(saved, query(c["query"]!)) == expect, "toggle \(c)")
        }
        for case let c as [String] in section("plain") {
            check(plain(c[0]) == c[1], "plain \(c[0]): \(plain(c[0]))")
        }
        let hit = (section("records")[1] as! [String: Any])["hit"]!
        let answer = try! JSONSerialization.data(withJSONObject: ["hits": ["total": 7, "hits": [hit, ["metadata": [:]]]]])
        let parsed = parseSearch(answer)
        check(parsed?.total == 7 && parsed?.records.count == 1, "search answer")
        check(parseSearch(Data("<html>".utf8)) == nil, "not JSON")
        print("\(checks - failures) of \(checks) checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A record as the cases write it, each key that `expect` has
    static func records(_ c: [String: Any]) {
        let about = c["about"]!
        guard let expect = c["expect"] as? [String: Any] else {
            return check(Record(hit: c["hit"]!) == nil, "record \(about): not left out")
        }
        guard let r = Record(hit: c["hit"]!) else { return check(false, "record \(about): left out") }
        let authors: [[Any]] = r.authors.map { [$0.fullName, $0.query, $0.affiliations] }
        let all: [String: Any?] = [
            "recid": r.recid, "title": r.title, "byline": r.byline, "date": r.date, "arxiv": r.arxiv,
            "categories": r.categories, "dois": r.dois, "texkey": r.texkey, "citations": r.citations,
            "citations_without_self": r.citationsWithoutSelf, "journals": r.journals, "pages": r.pages,
            "references": r.references, "document_types": r.documentTypes, "keywords": r.keywords,
            "report_numbers": r.reportNumbers, "authors": authors,
        ]
        for (key, want) in expect {
            let found = all[key] ?? nil
            check(same(found, want), "record \(about): \(key) is \(String(describing: found)), not \(want)")
        }
    }

    /// Whether a value is the JSON value of a case, `null` being nil
    static func same(_ a: Any?, _ b: Any) -> Bool {
        switch (a, b) {
        case (nil, is NSNull): true
        case (nil, _), (_, is NSNull): false
        case let (x as String, y as String): x == y
        case let (x as Int, y as Int): x == y
        case let (x as [Any], y as [Any]): x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        default: false
        }
    }
}
#endif
