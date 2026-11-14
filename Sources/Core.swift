// Everything in the spec (heplio-gtk's spec/SPEC.md): requests to INSPIRE, records, short names,
// CSL, plain text, the refdir rules, entries and queries.json, the search history, and finding
// and tags in the Library. Foundation only, no networking, so that it builds and is tested on
// Linux: the tests are at the end

import Foundation

let pageSize = 25
private let api = "https://inspirehep.net/api/literature"
private let listFields = "control_number,titles.title,first_author.full_name,author_count,earliest_date,abstracts.value,arxiv_eprints.value,citation_count,document_type"
private let paperFields = "control_number,titles.title,authors.full_name,authors.ids,earliest_date,abstracts.value,arxiv_eprints.value,arxiv_eprints.categories,dois.value,texkeys,citation_count,publication_info,number_of_pages,references.record,figures.url,figures.caption,collaborations.value,document_type"
/// The most results INSPIRE gives for a query
private let maxResults = 10_000
/// The folder, in the library, of what only Heplio reads
let appFolder = ".heplio"
private let historyLimit = 20

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Queries

/// A query with its name. `sort` is nil for relevance
struct Query: Hashable {
    var name: String
    var q: String
    var sort: String?
}

/// A sort of a list: the `sort` parameter, nil for relevance
struct Sort: Hashable {
    var sort: String?
    var name: String
}

let sorts = [Sort(sort: nil, name: "Relevance"), Sort(sort: "mostrecent", name: "Most Recent"),
             Sort(sort: "mostcited", name: "Most Cited")]

// MARK: - Requests

/// Percent-encodes all but the unreserved characters, `+` included, which INSPIRE reads as a space
func encode(_ s: String) -> String {
    var out = ""
    for b in s.utf8 {
        switch b {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
             UInt8(ascii: "_"), UInt8(ascii: "~"):
            out.append(Character(UnicodeScalar(b)))
        default:
            out += String(format: "%%%02X", b)
        }
    }
    return out
}

func listURL(_ q: String, sort: String?, page: Int) -> String {
    let sort = sort.map { "&sort=\(encode($0))" } ?? ""
    return "\(api)?q=\(encode(q.trimmed))\(sort)&size=\(pageSize)&page=\(page)&fields=\(encode(listFields))"
}

func paperURL(_ recid: Int) -> String {
    "\(api)?q=\(encode("recid:\(recid)"))&size=1&fields=\(encode(paperFields))"
}

func bibtexURL(_ recid: Int) -> String {
    "\(api)/\(recid)?format=bibtex"
}

func pdfURL(_ arxiv: String) -> String {
    "https://arxiv.org/pdf/\(arxiv)"
}

/// Whether there is a page after `page`
func hasMore(total: Int, page: Int) -> Bool {
    page * pageSize < min(total, maxResults)
}

/// `hits.total` and the records of a search. A hit that cannot be read is left out alone
func parseSearch(_ data: Data) throws -> (total: Int, records: [Record]) {
    let value = try JSON(parsing: data)
    guard let hits = value["hits"], let total = hits["total"]?.int, let list = hits["hits"]?.array else {
        throw CoreError.unexpectedAnswer
    }
    return (total, list.compactMap(Record.init(hit:)))
}

// MARK: - Records

struct Author: Hashable {
    var fullName: String
    var bai: String?

    var short: String { shortName(fullName) }

    /// The author's papers: by BAI, or by name without one
    var query: String {
        if let bai { return "a \(bai)" }
        return "a \"\(fullName)\""
    }
}

struct Figure: Hashable {
    var url: String
    /// TeX, as given
    var caption: String
}

/// An entry of `publication_info`. The fields INSPIRE gives as a string or a number are text
struct Publication: Hashable {
    var journalTitle, journalVolume, journalIssue, year, artid, pageStart, pageEnd: String?
    var material: String?
    var hasJournalTitle: Bool

    init?(_ json: JSON) {
        guard case .object = json else { return nil }
        func text(_ key: String) -> String? {
            switch json[key] {
            case .string(let s)?: s.trimmed.isEmpty ? nil : s.trimmed
            case .int(let n)?: String(n)
            case .double(let n)?: String(n)
            default: nil
            }
        }
        journalTitle = text("journal_title")
        journalVolume = text("journal_volume")
        journalIssue = text("journal_issue")
        year = text("year")
        artid = text("artid")
        pageStart = text("page_start")
        pageEnd = text("page_end")
        material = json["material"]?.string
        hasJournalTitle = json["journal_title"].map { $0 != .null } ?? false
    }

    /// `Adv.Theor.Math.Phys. 2 (1998) 231`
    var journal: String {
        [journalTitle, journalVolume, year.map { "(\($0))" }, artid ?? pageStart].compactMap { $0 }.joined(separator: " ")
    }
}

/// A hit of a list or a paper. A list's hit has only its first author
struct Record: Hashable {
    var recid: Int
    var title: String?
    var authors: [Author] = []
    var authorCount = 0
    var date: String?
    var abstract: String?
    var arxiv: String?
    var doi: String?
    var texkey: String?
    var citations: Int?
    var pages: Int?
    /// The primary arXiv category
    var category: String?
    /// The references that link to a record; nil without `references`
    var references: Int?
    var figures: [Figure] = []
    var collaborations: [String] = []
    /// The first of `document_type`
    var documentType: String?
    /// The entry of `publication_info` that the journal is made from
    var publication: Publication?

    /// The journal, as `Title Volume (Year) Page`
    var journal: String? { publication?.journal }

    init(recid: Int) {
        self.recid = recid
    }

    init?(hit: JSON) {
        guard let m = hit["metadata"], case .object = m else { return nil }
        guard let recid = m["control_number"]?.int ?? hit["id"]?.string.flatMap({ Int($0) }) else { return nil }
        self.recid = recid
        let firstValue = { (key: String) in m[key]?.array?.first?["value"]?.string }
        func author(_ a: JSON) -> Author? {
            guard let name = a["full_name"]?.string else { return nil }
            let bai = a["ids"]?.array?.first { $0["schema"]?.string == "INSPIRE BAI" }?["value"]?.string
            return Author(fullName: name, bai: bai)
        }
        if let list = m["authors"]?.array {
            authors = list.compactMap(author)
        } else if let first = m["first_author"] {
            authors = author(first).map { [$0] } ?? []
        }
        authorCount = m["author_count"]?.int ?? authors.count
        title = m["titles"]?.array?.first?["title"]?.string
        date = m["earliest_date"]?.string
        abstract = firstValue("abstracts")
        let eprint = m["arxiv_eprints"]?.array?.first
        arxiv = eprint?["value"]?.string
        category = eprint?["categories"]?.array?.first?.string
        doi = firstValue("dois")
        texkey = m["texkeys"]?.array?.first?.string
        citations = m["citation_count"]?.int
        pages = m["number_of_pages"]?.int
        references = m["references"]?.array.map { $0.filter { $0["record"].map { $0 != .null } ?? false }.count }
        figures = (m["figures"]?.array ?? []).compactMap { f in
            guard let url = f["url"]?.string else { return nil }
            let caption = f["caption"]?.string ?? ""
            // Some captions are only punctuation, such as " : "
            let useful = caption.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
            return Figure(url: url, caption: useful ? caption.trimmed : "")
        }
        collaborations = (m["collaborations"]?.array ?? []).compactMap { $0["value"]?.string }
        documentType = m["document_type"]?.array?.first?.string
        // The first with a `journal_title` whose `material` is `publication` or missing, else the
        // first with a `journal_title`
        let titled = (m["publication_info"]?.array ?? []).compactMap(Publication.init).filter(\.hasJournalTitle)
        publication = titled.first { $0.material == nil || $0.material == "publication" } ?? titled.first
    }

    /// The first author's short name, and ` et al.` if there are more
    var byline: String {
        let first = authors.first?.short ?? ""
        return authorCount > 1 ? "\(first) et al." : first
    }

    /// The citation key: the first texkey, if it is one, else `inspire:<recid>`
    var cslID: String {
        if let key = texkey, !key.isEmpty,
           key.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_:-".unicodeScalars.contains($0)) }) {
            return key
        }
        return "inspire:\(recid)"
    }

    /// The record as a CSL-JSON item, with `id` as its citation key
    func csl(id: String) -> JSON {
        let kind: String
        switch documentType {
        case "book", "proceedings": kind = "book"
        case "book chapter": kind = "chapter"
        case "thesis": kind = "thesis"
        case "conference paper": kind = "paper-conference"
        case "report": kind = "report"
        default: kind = publication != nil ? "article-journal" : "article"
        }
        let authors: [JSON]
        if collaborations.isEmpty {
            authors = self.authors.map { cslName($0.fullName) }
        } else {
            authors = collaborations.map { c in
                .object(["literal": .string(c.hasSuffix("Collaboration") ? c : "\(c) Collaboration")])
            }
        }
        let p = publication
        var page = p?.artid
        if page == nil, let start = p?.pageStart {
            page = p?.pageEnd.map { "\(start)-\($0)" } ?? start
        }
        return JSON.object([
            "id": .string(id),
            "type": .string(kind),
            "title": JSON(title.map(plain)),
            "author": .array(authors),
            "container-title": JSON(p?.journalTitle.map(spaced)),
            "volume": JSON(p?.journalVolume),
            "issue": JSON(p?.journalIssue),
            "page": JSON(page),
            "issued": date.map { JSON.object(["raw": .string($0)]) } ?? .null,
            "DOI": JSON(doi),
            "number-of-pages": pages.map { JSON.int($0) } ?? .null,
        ]).pruned ?? .object([:])
    }

    /// The entry's `sources.inspire`, fetched at `now`, with `id` as its citation key
    func source(now: String, id: String) -> JSON {
        JSON.object([
            "csl": csl(id: id),
            "fetched": .string(now),
            "recid": .int(recid),
            "arxiv": JSON(arxiv),
            "title": JSON(title),
        ]).pruned ?? .object([:])
    }
}

/// `Maldacena, Juan Martin` as a CSL name: `family` and `given`, or `literal` without a comma
private func cslName(_ full: String) -> JSON {
    guard let comma = full.firstIndex(of: ",") else { return .object(["literal": .string(full.trimmed)]) }
    let family = String(full[..<comma]).trimmed
    let given = String(full[full.index(after: comma)...]).trimmed
    return given.isEmpty ? .object(["family": .string(family)])
        : .object(["family": .string(family), "given": .string(given)])
}

/// A space after each `.` followed by a letter: `Phys.Lett.B` → `Phys. Lett. B`
private func spaced(_ journal: String) -> String {
    var out = ""
    let chars = Array(journal)
    for (i, c) in chars.enumerated() {
        out.append(c)
        if c == ".", i + 1 < chars.count, chars[i + 1].isLetter { out.append(" ") }
    }
    return out
}

/// `Maldacena, Juan Martin` → `J.M. Maldacena`; `He, Zhi-Guo` → `Z.-G. He`. A name without a comma
/// is kept as it is
func shortName(_ full: String) -> String {
    guard let comma = full.firstIndex(of: ",") else { return full.trimmed }
    let last = String(full[..<comma]).trimmed
    let initials = full[full.index(after: comma)...].split(whereSeparator: \.isWhitespace).map { word in
        word.split(separator: "-").compactMap(\.first).map { "\($0)." }.joined(separator: "-")
    }.joined()
    return initials.isEmpty ? last : "\(initials) \(last)"
}

// MARK: - Plain text

/// TeX, with some HTML or MathML, as plain Unicode text: `$H\to\gamma\gamma$` → `H→γγ`. INSPIRE's
/// text is not quite TeX: a bare `%`, `&`, or `#` is text, and an odd `$` is a dollar. No `$`, `\`,
/// TeX's braces, or tags are left
func plain(_ text: String) -> String {
    // `<sup>…</sup>` is a superscript, `<sub>` and `<inf>` a subscript; other tags are dropped
    var tex = ""
    var rest = Substring(text)
    while let start = rest.firstIndex(of: "<") {
        tex += rest[..<start]
        let tag = rest[rest.index(after: start)...]
        guard let first = tag.first, first.isASCII && first.isLetter || first == "/",
              let end = tag.firstIndex(of: ">") else {
            tex += "<"
            rest = tag
            continue
        }
        let closing = first == "/"
        let name = tag[..<end].drop { $0 == "/" }.prefix { $0 != " " && $0 != "/" }.lowercased()
        switch (name, closing) {
        case ("sup", false): tex += "$^{"
        case ("sub", false), ("inf", false): tex += "$_{"
        case ("sup", true), ("sub", true), ("inf", true): tex += "}$"
        default: tex += " "
        }
        rest = tag[tag.index(after: end)...]
    }
    tex += rest
    var parser = TeX(decodeEntities(tex))
    let out = parser.convert(math: false, closing: nil)
    return out.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `&amp;`, `&#945;`, `&#x3B1;`, and the few named entities INSPIRE uses
private func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                   "ndash": "–", "mdash": "—", "hellip": "…", "times": "×", "plusmn": "±"]
    var out = ""
    var rest = Substring(text)
    while let amp = rest.firstIndex(of: "&") {
        out += rest[..<amp]
        let after = rest[rest.index(after: amp)...]
        if let semi = after.prefix(10).firstIndex(of: ";") {
            let name = String(after[..<semi])
            var value: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                value = UInt32(name.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                value = UInt32(name.dropFirst()).flatMap(UnicodeScalar.init).map { String($0) }
            } else {
                value = named[name]
            }
            if let value {
                out += value
                rest = after[after.index(after: semi)...]
                continue
            }
        }
        out += "&"
        rest = after
    }
    return out + rest
}

/// A small converter of TeX to text: commands become their symbols, scripts become Unicode
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
            case ",", ";", ":", " ", "\n": return " "
            case "!", "/", "-": return ""
            case "\\": return " "
            default: return String(first)
            }
        }
        var name = ""
        while !atEnd && s[i].isASCII && s[i].isLetter {
            name.append(s[i])
            i += 1
        }
        if math { skipSpaces() }
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
        guard !text.isEmpty else { return "" }
        return text.map { String($0) + mark }.joined()
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
        "bar": "\u{304}", "overline": "\u{305}", "tilde": "\u{303}", "widetilde": "\u{303}", "hat": "\u{302}",
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
        "textasciitilde": "~", "textdegree": "°", "textmu": "µ", "textperthousand": "‰", "LaTeX": "LaTeX",
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

// MARK: - JSON

/// A JSON value, read and written by Foundation's JSONDecoder and JSONEncoder. Objects have no
/// order: files are compared as values. Numbers that are whole are `int`
enum JSON: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(_ string: String?) {
        self = string.map { .string($0) } ?? .null
    }

    init(parsing data: Data) throws {
        self = try JSONDecoder().decode(JSON.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Int.self) { self = .int(n) }
        else if let n = try? c.decode(Double.self) { self = .double(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let n): try c.encode(n)
        case .double(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Numbers are equal by value: `1.0` is `1`
    static func == (a: JSON, b: JSON) -> Bool {
        switch (a, b) {
        case (.null, .null): true
        case (.bool(let x), .bool(let y)): x == y
        case (.int(let x), .int(let y)): x == y
        case (.double(let x), .double(let y)): x == y
        case (.int(let x), .double(let y)), (.double(let y), .int(let x)): Double(x) == y
        case (.string(let x), .string(let y)): x == y
        case (.array(let x), .array(let y)): x == y
        case (.object(let x), .object(let y)): x == y
        default: false
        }
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// A whole number
    var int: Int? {
        switch self {
        case .int(let n): n
        case .double(let n) where n.rounded() == n && abs(n) < 1e15: Int(n)
        default: nil
        }
    }

    var array: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var object: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Without empty fields, recursively: `null`, `""`, `[]` and `{}`. nil if it is empty itself
    var pruned: JSON? {
        switch self {
        case .null: return nil
        case .string(let s): return s.isEmpty ? nil : self
        case .array(let a):
            let items = a.compactMap(\.pruned)
            return items.isEmpty ? nil : .array(items)
        case .object(let o):
            let fields = o.compactMapValues(\.pruned)
            return fields.isEmpty ? nil : .object(fields)
        default: return self
        }
    }

    /// Indented, with a newline at the end
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

/// The keys of the top-level object's `sources`, in the order of the file. refdir layers the
/// resolved item in that order, which JSONDecoder does not keep; this reads only the order, and
/// JSONDecoder reads the values
func sourceOrder(_ data: Data) -> [String] {
    let b = [UInt8](data)
    let (quote, backslash, colon, comma) = (UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: ":"), UInt8(ascii: ","))
    let (open, close, openList, closeList) = (UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"))
    var i = 0
    /// The index of the quote that ends the string starting at `start`
    func stringEnd(_ start: Int) -> Int {
        var j = start + 1
        while j < b.count && b[j] != quote { j += b[j] == backslash ? 2 : 1 }
        return min(j, b.count - 1)
    }
    func skipSpace() {
        while i < b.count && [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
    }
    func skipValue() {
        guard i < b.count else { return }
        if b[i] == quote {
            i = stringEnd(i) + 1
        } else if b[i] == open || b[i] == openList {
            var depth = 0
            while i < b.count {
                if b[i] == quote { i = stringEnd(i) }
                else if b[i] == open || b[i] == openList { depth += 1 }
                else if b[i] == close || b[i] == closeList {
                    depth -= 1
                    if depth == 0 { i += 1; return }
                }
                i += 1
            }
        } else {
            while i < b.count && ![comma, close, closeList, 0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
        }
    }
    /// Reads the object at `i`, calling `found` with each key while `i` is at its value, which
    /// `found` may read. Ends after the object
    func members(_ found: (String) -> Void) {
        guard i < b.count, b[i] == open else { return skipValue() }
        i += 1
        while true {
            skipSpace()
            guard i < b.count, b[i] != close else { i += 1; return }
            guard b[i] == quote else { return }
            let end = stringEnd(i)
            let key = (try? JSONDecoder().decode(String.self, from: Data(b[i...end]))) ?? ""
            i = end + 1
            skipSpace()
            guard i < b.count, b[i] == colon else { return }
            i += 1
            skipSpace()
            let start = i
            found(key)
            if i == start { skipValue() }
            skipSpace()
            if i < b.count, b[i] == comma { i += 1 }
        }
    }
    var order: [String] = []
    skipSpace()
    members { key in
        if key == "sources" { members { order.append($0) } }
    }
    return order
}

// MARK: - refdir

/// The file that makes a folder an entry
let entryFile = "entry.json"

enum CoreError: LocalizedError {
    case notJSON, notObject, notV1(JSON?), tags, emptyTag, unreadable, notSaved, noArxiv, notPDF, unexpectedAnswer

    var errorDescription: String? {
        switch self {
        case .notJSON: "Its \(entryFile) is not JSON."
        case .notObject: "Its \(entryFile) is not a JSON object."
        case .notV1(nil): "Its \(entryFile) has no version."
        case .notV1: "Its \(entryFile) is of another version."
        case .tags: "The paper's tags are not all text, so Heplio does not change them."
        case .emptyTag: "A tag cannot be empty."
        case .unreadable: "The file cannot be read."
        case .notSaved: "The paper is not in the library."
        case .noArxiv: "The paper is not on arXiv."
        case .notPDF: "arXiv did not send a PDF."
        case .unexpectedAnswer: "INSPIRE gave an unexpected answer."
        }
    }
}

/// Whether a name is for apps: one starting with `.`
func isHidden(_ name: String) -> Bool { name.hasPrefix(".") }

/// The order of names: ASCII case ignored, then code point order (UTF-8 byte order)
func namePrecedes(_ a: String, _ b: String) -> Bool {
    let (x, y) = (Array(a.utf8), Array(b.utf8))
    let lower = { (s: [UInt8]) in s.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 } }
    let (lx, ly) = (lower(x), lower(y))
    return lx != ly ? lx.lexicographicallyPrecedes(ly) : x.lexicographicallyPrecedes(y)
}

private func isDirectory(_ url: URL) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
}

private func isFile(_ url: URL) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && !dir.boolValue
}

private func names(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path)
}

/// The entries' folders: those directly in the library, not starting with `.`, with `entry.json`.
/// In name order
func entryFolders(_ library: URL) throws -> [URL] {
    try names(in: library).filter { !isHidden($0) }.sorted(by: namePrecedes)
        .map { library.appendingPathComponent($0) }
        .filter { isDirectory($0) && isFile($0.appendingPathComponent(entryFile)) }
}

/// A readable entry
struct RefdirEntry {
    let dir: URL
    /// `entry.json`
    var data: [String: JSON]
    /// The keys of `sources`, in the order of the file
    var order: [String]

    /// Reads `entry.json` in `dir`: an object with `v` 1 (`1.0` is 1)
    init(_ dir: URL) throws {
        self.dir = dir
        let bytes = try Data(contentsOf: dir.appendingPathComponent(entryFile))
        guard let value = try? JSON(parsing: bytes) else { throw CoreError.notJSON }
        guard case .object(let data) = value else { throw CoreError.notObject }
        guard data["v"] == .int(1) else { throw CoreError.notV1(data["v"]) }
        self.data = data
        order = sourceOrder(bytes)
    }

    var name: String { dir.lastPathComponent }

    /// The layers of the resolved item, earliest first: each `sources.*.csl` in key order, then
    /// `csl`. Those that are not objects are left out
    private var layers: [[String: JSON]] {
        let sources = data["sources"]?.object ?? [:]
        // Keys the order missed, if any, come after, by name
        let keys = order.filter { sources[$0] != nil } + sources.keys.filter { !order.contains($0) }.sorted()
        return (keys.map { sources[$0]?["csl"] } + [data["csl"]]).compactMap { $0?.object }
    }

    /// A field of the resolved item: a later layer's field replaces an earlier one whole
    func field(_ key: String) -> JSON? {
        layers.reversed().lazy.compactMap { $0[key] }.first
    }

    /// The citation key: the resolved `csl.id`, if it is a string
    var id: String? { field("id")?.string }

    /// `tags`, skipping what is not a string
    var tags: [String] { data["tags"]?.array?.compactMap(\.string) ?? [] }

    var inspire: JSON? { data["sources"]?["inspire"] }
    var recid: Int? { if case .int(let n)? = inspire?["recid"] { n } else { nil } }
    var arxiv: String? { inspire?["arxiv"]?.string }

    /// The main file: the first file directly in the folder by name, not `entry.json` nor
    /// starting with `.`
    func mainFile() -> URL? {
        let files = ((try? names(in: dir)) ?? []).filter { !isHidden($0) && $0 != entryFile }
            .filter { isFile(dir.appendingPathComponent($0)) }
        return files.min(by: namePrecedes).map { dir.appendingPathComponent($0) }
    }
}

/// The library's entries, in name order, and the folders with an `entry.json` that cannot be read
struct RefdirLibrary {
    var entries: [RefdirEntry] = []
    var unreadable: [(dir: URL, error: Error)] = []

    init(_ folder: URL) throws {
        for dir in try entryFolders(folder) {
            do { entries.append(try RefdirEntry(dir)) } catch { unreadable.append((dir, error)) }
        }
    }
}

/// A folder name for a new entry: the citation key with `:` → `-`, then with `-2`, `-3`, …
/// until no name in the library is the same, ignoring ASCII case
func freeName(_ library: URL, id: String) throws -> String {
    let lower = asciiLowercased
    let taken = Set(try names(in: library).map(lower))
    let base = id.replacingOccurrences(of: ":", with: "-")
    if !taken.contains(lower(base)) { return base }
    return (2...).lazy.map { "\(base)-\($0)" }.first { !taken.contains(lower($0)) }!
}

/// Whether another entry's citation key is `id`, ignoring ASCII case. `own` is the entry's
/// folder, left out
func idTaken(_ library: URL, id: String, own: URL?) throws -> Bool {
    try RefdirLibrary(library).entries.contains { e in
        e.id.map { sameID($0, id) } == true && e.dir.standardizedFileURL != own?.standardizedFileURL
    }
}

private func sameID(_ a: String, _ b: String) -> Bool {
    asciiLowercased(a) == asciiLowercased(b)
}

/// ASCII letters in lower case; the rest as it is
private func asciiLowercased(_ s: String) -> String {
    String(decoding: s.utf8.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }, as: UTF8.self)
}

/// Writes `data` to a temporary file next to `url`, whose name starts with `.`, then renames it
func writeAtomic(_ url: URL, _ data: Data) throws {
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).tmp")
    do {
        try data.write(to: tmp)
        guard rename(tmp.path, url.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    } catch {
        try? FileManager.default.removeItem(at: tmp)
        throw error
    }
}

/// `tags`, strictly: an error if it is not an array of strings, so that writing does not lose
/// what someone put there
private func strictTags(_ data: [String: JSON]) throws -> [String] {
    guard let tags = data["tags"] else { return [] }
    guard let list = tags.array else { throw CoreError.tags }
    return try list.map { item -> String in
        guard let tag = item.string else { throw CoreError.tags }
        return tag
    }
}

/// Reads the entry in `dir` again, edits its tags, and writes them without repeats, the first of
/// each kept. Nothing is written if they are unchanged
@discardableResult
func editTags(_ dir: URL, _ edit: (inout [String]) throws -> Void) throws -> [String] {
    var entry = try RefdirEntry(dir)
    let old = try strictTags(entry.data)
    var new = old
    try edit(&new)
    var seen = Set<String>()
    new = new.filter { seen.insert($0).inserted }
    if new != old {
        entry.data["tags"] = JSON.array(new.map { .string($0) }).pruned
        try writeAtomic(dir.appendingPathComponent(entryFile), JSON.object(entry.data).data())
    }
    return new
}

/// The namespace and the value, split at the first `:`. A tag without `:` has no namespace
func splitTag(_ tag: String) -> (namespace: String?, value: String) {
    guard let colon = tag.firstIndex(of: ":") else { return (nil, tag) }
    return (String(tag[..<colon]), String(tag[tag.index(after: colon)...]))
}

/// The order of tags in lists: those without a namespace first, then by namespace, then by value,
/// each in name order
func tagPrecedes(_ a: String, _ b: String) -> Bool {
    let (x, y) = (splitTag(a), splitTag(b))
    if (x.namespace != nil) != (y.namespace != nil) { return x.namespace == nil }
    let (nx, ny) = (x.namespace ?? "", y.namespace ?? "")
    if nx != ny { return namePrecedes(nx, ny) }
    return namePrecedes(x.value, y.value)
}

/// The number of tags suggested while one is typed
let suggestionCount = 5

/// The library's tags to offer while `text` is typed as a new tag of a paper: those it does not
/// have whose text, or value without the namespace, starts with `text`, ignoring case
func suggestions(_ known: [String], own: [String], text: String) -> [String] {
    let text = text.trimmed.lowercased()
    guard !text.isEmpty else { return [] }
    let starts = { (tag: String) in tag.lowercased().hasPrefix(text) || splitTag(tag).value.lowercased().hasPrefix(text) }
    return Array(known.filter { !own.contains($0) && starts($0) }.prefix(suggestionCount))
}

// MARK: - Library

/// An entry of the library, as listed
struct SavedPaper: Hashable, Identifiable {
    /// The entry's folder
    var dir: URL
    /// `sources.inspire.recid`; nil for an unreadable entry
    var recid: Int?
    /// From the resolved item
    var title: String?
    var byline = ""
    var date: String?
    var added: String?
    var arxiv: String?
    /// The main file, if it is a PDF
    var pdf: URL?
    /// The PDF that Heplio downloads, if it is there
    var arxivPDF: URL?
    /// `tags`, those that are strings
    var tags: [String] = []
    /// What finding looks in, folded
    var text = ""

    var id: URL { dir }
    var name: String { dir.lastPathComponent }

    /// Whether the Library's search finds it: every word of `search` is in its text
    func matches(_ search: String) -> Bool { wordsIn(search, text) }

    func has(tag: String) -> Bool { tags.contains(tag) }
}

/// Whether the Library's search lists the tag above the papers: the search has text, and every
/// word of it is in the tag
func tagMatches(_ tag: String, _ search: String) -> Bool {
    !search.trimmed.isEmpty && wordsIn(search, fold(tag))
}

private func wordsIn(_ search: String, _ folded: String) -> Bool {
    fold(search).split(whereSeparator: \.isWhitespace).allSatisfy { folded.contains($0) }
}

/// For finding: decomposed, without combining marks, in lower case (`Gürsey` → `gursey`)
func fold(_ text: String) -> String {
    let marks: Set<Unicode.GeneralCategory> = [.nonspacingMark, .spacingMark, .enclosingMark]
    var scalars = String.UnicodeScalarView()
    scalars.append(contentsOf: text.decomposedStringWithCanonicalMapping.unicodeScalars
        .filter { !marks.contains($0.properties.generalCategory) })
    return String(scalars).lowercased()
}

/// The name of the PDF Heplio downloads: `hep-th/9711200` → `hep-th-9711200.pdf`
func arxivPDFName(_ arxiv: String) -> String {
    arxiv.replacingOccurrences(of: "/", with: "-") + ".pdf"
}

/// A CSL name, if its fields are strings
private struct Name {
    var literal, family, given: String?

    init?(_ json: JSON) {
        guard let o = json.object else { return nil }
        for key in ["literal", "family", "given"] where o[key] != nil && o[key] != .null && o[key]?.string == nil {
            return nil
        }
        (literal, family, given) = (o["literal"]?.string, o["family"]?.string, o["given"]?.string)
    }

    /// `Juan Martin Maldacena`
    var full: String? {
        let full = [literal, given, family].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? nil : full
    }

    /// `J.M. Maldacena`
    var short: String? {
        if let literal { return literal }
        if let family, let given { return shortName("\(family), \(given)") }
        return family
    }
}

/// A CSL date as shown: its `raw`, or else its first `date-parts`, as `1997-11`
private func dateText(_ json: JSON?) -> String? {
    guard let o = json?.object else { return nil }
    if let raw = o["raw"], raw != .null {
        return raw.string
    }
    guard let parts = o["date-parts"]?.array?.first?.array, !parts.isEmpty else { return nil }
    let numbers = parts.compactMap(\.int)
    guard numbers.count == parts.count else { return nil }
    return numbers.enumerated().map { $0 > 0 ? String(format: "%02d", $1) : String($1) }.joined(separator: "-")
}

private func saved(_ entry: RefdirEntry) -> SavedPaper {
    let list = entry.field("author")?.array
    let authors = list.map { $0.compactMap(Name.init) }.flatMap { $0.count == list?.count ? $0 : nil } ?? []
    let first = authors.first?.short ?? ""
    let title = entry.field("title")?.string
    let date = dateText(entry.field("issued"))
    let tags = entry.tags
    let names = authors.flatMap { [$0.full, $0.short] }.compactMap { $0 }
    let other = [entry.field("id")?.string, entry.field("container-title")?.string, date, entry.arxiv].compactMap { $0 }
    let text = ([title].compactMap { $0 } + names + other + tags).joined(separator: "\n")
    let main = entry.mainFile()
    let arxivPDF = entry.arxiv.map { entry.dir.appendingPathComponent(arxivPDFName($0)) }
    return SavedPaper(
        dir: entry.dir, recid: entry.recid, title: title,
        byline: authors.count > 1 ? "\(first) et al." : first,
        date: date, added: entry.data["added"]?.string, arxiv: entry.arxiv,
        pdf: main.flatMap { $0.pathExtension.lowercased() == "pdf" ? $0 : nil },
        arxivPDF: arxivPDF.flatMap { isFile($0) ? $0 : nil },
        tags: tags, text: fold(text))
}

/// The library's papers, newest `added` first, then by folder name: the entries from INSPIRE, and
/// the unreadable ones. An entry of a later version is skipped, as refdir says
func readLibrary(_ folder: URL) -> [SavedPaper] {
    guard let library = try? RefdirLibrary(folder) else { return [] }
    let readable = library.entries.filter { $0.recid != nil }.map(saved)
    let unreadable = library.unreadable.filter { item in
        if case CoreError.notV1(_?) = item.error { return false }
        return true
    }.map { SavedPaper(dir: $0.dir, text: fold($0.dir.lastPathComponent)) }
    return (readable + unreadable).sorted { a, b in
        if a.added != b.added {
            guard let x = a.added else { return false }
            guard let y = b.added else { return true }
            return Array(y.utf8).lexicographicallyPrecedes(Array(x.utf8))
        }
        return namePrecedes(a.name, b.name)
    }
}

/// The paper's entry: of the readable ones with its recid, the first by folder name
private func find(_ folder: URL, _ recid: Int) throws -> RefdirEntry? {
    try RefdirLibrary(folder).entries.first { $0.recid == recid }
}

func entry(of recid: Int, in folder: URL) -> SavedPaper? {
    ((try? find(folder, recid)) ?? nil).map(saved)
}

private func one(_ folder: URL, _ recid: Int) throws -> SavedPaper {
    guard let paper = entry(of: recid, in: folder) else { throw CoreError.notSaved }
    return paper
}

/// The citation key for an entry without one: the record's, unless another entry has it; then
/// `inspire:<recid>`. `own` is the entry's folder
private func newID(_ folder: URL, _ record: Record, own: URL?) throws -> String {
    let id = record.cslID
    return try idTaken(folder, id: id, own: own) ? "inspire:\(record.recid)" : id
}

/// Creates the paper's entry, or updates its `sources.inspire`. `now` is the time for `added` and
/// `fetched`. Says whether it wrote the file
@discardableResult
func savePaper(_ folder: URL, _ record: Record, now: String) throws -> Bool {
    guard var entry = try find(folder, record.recid) else {
        let id = try newID(folder, record, own: nil)
        let dir = folder.appendingPathComponent(try freeName(folder, id: id))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = JSON.object(["v": .int(1), "sources": .object(["inspire": record.source(now: now, id: id)]),
                                "added": .string(now)])
        try writeAtomic(dir.appendingPathComponent(entryFile), data.data())
        return true
    }
    let old = entry.inspire ?? .null
    // The citation key the entry has stays: a key that changed would break the user's \cite
    let id = try old["csl"]?["id"]?.string ?? newID(folder, record, own: entry.dir)
    guard case .object(var source) = record.source(now: now, id: id) else { return false }
    // So does the plain title while its TeX is the same: another device may make it otherwise
    if old["title"] == source["title"], let title = old["csl"]?["title"], title.string != nil,
       case .object(var csl)? = source["csl"] {
        csl["title"] = title
        source["csl"] = .object(csl)
    }
    var unchanged = source
    unchanged["fetched"] = old["fetched"]
    if old == .object(unchanged) { return false }
    var sources = entry.data["sources"]?.object ?? [:]
    sources["inspire"] = .object(source)
    entry.data["sources"] = .object(sources)
    try writeAtomic(entry.dir.appendingPathComponent(entryFile), JSON.object(entry.data).data())
    return true
}

/// Removes the paper's entry, its folder, with `delete`
func removePaper(_ folder: URL, _ recid: Int, delete: (URL) throws -> Void) throws {
    try delete(one(folder, recid).dir)
}

/// The tags of `papers`, each with the number of papers that have it, in refdir's order
func tagCounts(_ papers: [SavedPaper]) -> [(tag: String, count: Int)] {
    var counts: [String: Int] = [:]
    for p in papers {
        for t in Set(p.tags) { counts[t, default: 0] += 1 }
    }
    return counts.map { ($0.key, $0.value) }.sorted { tagPrecedes($0.tag, $1.tag) }
}

/// Adds a tag, trimmed, at the end of the paper's tags, unless it has it
func addTag(_ folder: URL, _ recid: Int, _ tag: String) throws {
    let dir = try one(folder, recid).dir
    let tag = tag.trimmed
    try editTags(dir) { tags in
        guard !tag.isEmpty else { throw CoreError.emptyTag }
        if !tags.contains(tag) { tags.append(tag) }
    }
}

func removeTag(_ folder: URL, _ recid: Int, _ tag: String) throws {
    try editTags(try one(folder, recid).dir) { $0.removeAll { $0 == tag } }
}

/// Keeps a PDF downloaded from arXiv in the paper's entry
func savePDF(_ folder: URL, _ recid: Int, _ data: Data) throws {
    let p = try one(folder, recid)
    guard let arxiv = p.arxiv else { throw CoreError.noArxiv }
    guard data.starts(with: Data("%PDF-".utf8)) else { throw CoreError.notPDF }
    try writeAtomic(p.dir.appendingPathComponent(arxivPDFName(arxiv)), data)
}

/// Removes the PDF downloaded from arXiv with `delete`, if it is there
func removePDF(_ folder: URL, _ recid: Int, delete: (URL) throws -> Void) throws {
    if let pdf = try one(folder, recid).arxivPDF { try delete(pdf) }
}

// MARK: - Saved queries

/// `queries.json`
enum Queries: Equatable {
    case missing
    case unreadable
    case list([Query])

    /// The queries, none if the file is missing or unreadable
    var list: [Query] {
        if case .list(let list) = self { return list }
        return []
    }
}

func queriesURL(_ folder: URL) -> URL {
    folder.appendingPathComponent(appFolder).appendingPathComponent("queries.json")
}

/// The items of `queries.json`, with the keys Heplio does not know. nil if there is none
private func readQueries(_ folder: URL) throws -> [[String: JSON]]? {
    let url = queriesURL(folder)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let items = (try? JSON(parsing: Data(contentsOf: url)))?.array else { throw CoreError.unreadable }
    let optional = { (v: JSON?) in v == nil || v == .null || v?.string != nil }
    return try items.map { item in
        guard let o = item.object, let q = o["q"]?.string, !q.isEmpty, optional(o["name"]), optional(o["sort"]) else {
            throw CoreError.unreadable
        }
        return o
    }
}

private func query(_ item: [String: JSON]) -> Query {
    let q = item["q"]?.string ?? ""
    return Query(name: item["name"]?.string ?? q, q: q, sort: item["sort"]?.string)
}

func readSavedQueries(_ folder: URL) -> Queries {
    do {
        guard let items = try readQueries(folder) else { return .missing }
        return .list(items.map(query))
    } catch {
        return .unreadable
    }
}

/// Reads `queries.json` again and changes it. `change` says whether it changed anything
private func changeQueries(_ folder: URL, _ change: (inout [[String: JSON]]) -> Bool) throws {
    var items = try readQueries(folder) ?? []
    guard change(&items) else { return }
    try FileManager.default.createDirectory(at: folder.appendingPathComponent(appFolder), withIntermediateDirectories: true)
    try writeAtomic(queriesURL(folder), JSON.array(items.map { .object($0) }).data())
}

func addQuery(_ folder: URL, _ q: Query) throws {
    try changeQueries(folder) { items in
        guard !items.contains(where: { query($0).q == q.q && query($0).sort == q.sort }) else { return false }
        items.append(["name": .string(q.name), "q": .string(q.q), "sort": JSON(q.sort)].compactMapValues(\.pruned))
        return true
    }
}

func removeQuery(_ folder: URL, at index: Int) throws {
    try changeQueries(folder) { items in
        guard items.indices.contains(index) else { return false }
        items.remove(at: index)
        return true
    }
}

func moveQuery(_ folder: URL, from: Int, to: Int) throws {
    try changeQueries(folder) { items in
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return false }
        items.insert(items.remove(at: from), at: to)
        return true
    }
}

func renameQuery(_ folder: URL, at index: Int, to name: String) throws {
    try changeQueries(folder) { items in
        guard items.indices.contains(index), items[index]["name"]?.string != name else { return false }
        items[index]["name"] = .string(name)
        return true
    }
}

/// When the user chooses a folder: a new library gets an example query
func chooseFolder(_ folder: URL) throws {
    guard !FileManager.default.fileExists(atPath: queriesURL(folder).path) else { return }
    try addQuery(folder, Query(name: "hep-th, last 7 days", q: "arxiv_eprints.categories:hep-th and de > today - 7",
                               sort: "mostrecent"))
}

// MARK: - Search history

/// Adds a search to the top of the recent searches
func remember(_ history: inout [String], _ text: String) {
    let text = text.trimmed
    guard !text.isEmpty else { return }
    history.removeAll { $0 == text }
    history.insert(text, at: 0)
    if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
}

/// Removes a search from the recent searches
func forget(_ history: inout [String], _ text: String) {
    history.removeAll { $0 == text }
}

/// The time now in UTC, as `2026-11-14T10:00:00Z`, for `added` and `fetched`
func timestamp(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
}

// MARK: - Tests

// Linux only: the app never builds this. Run with
//   swiftc -parse-as-library Sources/Core.swift -o /tmp/heplio-spec && /tmp/heplio-spec
// It runs spec/cases.json of this project, or the file whose path it is given
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

    static func tmpdir(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("heplio-\(name)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file's text as JSON if it is JSON, so that files are compared as values, not as text
    static func content(_ text: String) -> JSON {
        (try? JSON(parsing: Data(text.utf8))) ?? .string(text)
    }

    /// Writes `{"dir/name": "text"}` into `folder`
    static func writeTree(_ folder: URL, _ files: JSON) {
        for (path, text) in files.object ?? [:] {
            let url = folder.appendingPathComponent(path)
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(text.string!.utf8).write(to: url)
        }
    }

    /// The files of `folder`, by path, each as `content`
    static func readTree(_ folder: URL) -> [String: JSON] {
        var out: [String: JSON] = [:]
        func walk(_ dir: URL, _ prefix: String) {
            for name in try! FileManager.default.contentsOfDirectory(atPath: dir.path) {
                let url = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    walk(url, prefix + name + "/")
                } else {
                    out[prefix + name] = content(String(decoding: try! Data(contentsOf: url), as: UTF8.self))
                }
            }
        }
        walk(folder, "")
        return out
    }

    /// Leaves out the CSL item's title in `found` where `expect` leaves it out, after checking that
    /// no TeX or HTML is left in it: plain text is up to the platform
    static func loosen(_ found: JSON, _ expect: JSON?, path: [String]) -> JSON {
        guard let key = path.first else {
            guard case .object(var csl) = found, expect?["title"] == nil else { return found }
            if let title = csl.removeValue(forKey: "title")?.string {
                check(!title.contains { "$\\{}<>".contains($0) }, "plain title: \(title)")
            }
            return .object(csl)
        }
        guard case .object(var o) = found, let inner = o[key] else { return found }
        o[key] = loosen(inner, expect?[key], path: Array(path.dropFirst()))
        return .object(o)
    }

    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("spec/cases.json").path
        let cases = try JSON(parsing: Data(contentsOf: URL(fileURLWithPath: path)))
        specCases(cases)
        plainText()
        jsonFiles()
        refdirRules()
        listRecords()
        print(failures == 0 ? "ok: \(checks) checks" : "\(failures) of \(checks) checks failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The cases every Heplio app shares, run as the spec says (SPEC.md, "Test cases")
    static func specCases(_ cases: JSON) {
        let now = cases["now"]!.string!
        func record(_ c: JSON) -> Record {
            if let m = c["metadata"] { return Record(hit: .object(["metadata": m]))! }
            return Record(hit: cases["records"]![String(c["recid"]!.int!)]!)!
        }

        for c in cases["urls"]!.array! {
            let url: String
            if let l = c["list"] {
                url = listURL(l["q"]!.string!, sort: l["sort"]?.string, page: l["page"]!.int!)
            } else if let arxiv = c["pdf"]?.string {
                url = pdfURL(arxiv)
            } else if let recid = c["paper"]?.int {
                url = paperURL(recid)
            } else {
                url = bibtexURL(c["bibtex"]!.int!)
            }
            check(url == c["expect"]!.string!, "url \(c["name"]!.string!): \(url)")
        }
        for c in cases["paging"]!.array! {
            let more = hasMore(total: c["total"]!.int!, page: c["page"]!.int!)
            check(.bool(more) == c["more"]!, "paging \(c)")
        }
        for c in cases["names"]!.array! {
            let found = shortName(c["full_name"]!.string!)
            check(found == c["expect"]!.string!, "name \(c): \(found)")
        }
        for c in cases["authors"]!.array! {
            let r = Record(hit: .object(["metadata": .object(["control_number": .int(1), "authors": .array([c["author"]!])])]))
            check(r?.authors.first?.query == c["expect"]!.string!, "author \(c)")
        }
        for c in cases["details"]!.array! {
            let (r, e, name) = (record(c), c["expect"]!, c["name"]!.string!)
            check(JSON(r.journal) == e["journal"]!, "\(name): journal \(String(describing: r.journal))")
            check((r.pages.map { .int($0) } ?? .null) == e["pages"]!, "\(name): pages")
            check(JSON(r.category) == e["category"]!, "\(name): category")
            check((r.references.map { .int($0) } ?? .null) == e["references"]!, "\(name): references")
            let figures = JSON.array(r.figures.map { .array([.string($0.url), .string($0.caption)]) })
            check(figures == e["figures"]!, "\(name): figures \(r.figures)")
        }
        for c in cases["csl"]!.array! {
            let r = record(c)
            let csl = loosen(r.csl(id: r.cslID), c["expect"], path: [])
            check(csl == c["expect"]!, "csl \(c["name"]!.string!): \(csl)")
        }

        for c in cases["entries"]!.array! {
            let name = c["name"]!.string!
            let folder = tmpdir("entry")
            writeTree(folder, c["files"]!)
            let r = record(c)
            let ok: Bool
            do {
                switch c["do"]!.string! {
                case "save": try savePaper(folder, r, now: now)
                case "remove": try removePaper(folder, r.recid) { try FileManager.default.removeItem(at: $0) }
                case "pdf": try savePDF(folder, r.recid, Data(c["data"]!.string!.utf8))
                case "remove_pdf": try removePDF(folder, r.recid) { try FileManager.default.removeItem(at: $0) }
                case "add_tag": try addTag(folder, r.recid, c["tag"]!.string!)
                case "remove_tag": try removeTag(folder, r.recid, c["tag"]!.string!)
                case let other: fatalError(other)
                }
                ok = true
            } catch {
                ok = false
            }
            check(ok == (c["ok"].map { $0 == .bool(true) } ?? true), "\(name): ok")
            let after = (c["after"] ?? c["files"]!).object!
            let expect = after.mapValues { content($0.string!) }
            let found = readTree(folder).reduce(into: [String: JSON]()) { out, file in
                out[file.key] = loosen(file.value, expect[file.key], path: ["sources", "inspire", "csl"])
            }
            check(found == expect, "\(name): \(found.mapValues { (try? String(decoding: $0.data(), as: UTF8.self)) ?? "" })")
        }

        let library = cases["library"]!
        let folder = tmpdir("library")
        writeTree(folder, library["files"]!)
        let listed = readLibrary(folder)
        let rows = JSON.array(listed.map { p in
            .array([.string(p.name), p.recid.map { .int($0) } ?? .null, .bool(p.recid != nil),
                    JSON(p.pdf?.lastPathComponent), JSON(p.title), .string(p.byline), JSON(p.date)])
        })
        check(rows == library["expect"]!, "library: \(rows)")
        let tags = JSON.array(tagCounts(listed).map { .array([.string($0.tag), .int($0.count)]) })
        check(tags == library["tags"]!, "tags: \(tags)")
        for f in library["find"]!.array! {
            let search = f.array![0].string!
            let found = listed.filter { $0.matches(search) }.map(\.name)
            check(found == f.array![1].array!.map { $0.string! }, "find \(search): \(found)")
            let tags = tagCounts(listed).map(\.tag).filter { tagMatches($0, search) }
            let expect = f.array!.count > 2 ? f.array![2].array!.map { $0.string! } : []
            check(tags == expect, "find tags \(search): \(tags)")
        }
        for t in library["tagged"]!.array! {
            let tag = t.array![0].string!
            let found = listed.filter { $0.has(tag: tag) }.map(\.name)
            check(found == t.array![1].array!.map { $0.string! }, "tagged \(tag): \(found)")
        }

        for c in cases["queries"]!.array! {
            let name = c["name"]!.string!
            let folder = tmpdir("queries")
            let url = queriesURL(folder)
            let before = c["file"]?.string
            if let before {
                try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try! Data(before.utf8).write(to: url)
            }
            let readable = c["readable"].map { $0 == .bool(true) } ?? true
            switch readSavedQueries(folder) {
            case .unreadable: check(!readable, "\(name): unreadable")
            case .missing: check(before == nil, "\(name): missing")
            case .list(let found):
                check(readable, "\(name): readable")
                if let expect = c["list"]?.array {
                    let list = expect.map { e in
                        Query(name: e.array![0].string!, q: e.array![1].string!, sort: e.array![2].string)
                    }
                    check(found == list, "\(name): \(found)")
                }
            }
            guard let action = c["do"] else { continue }
            let text = { (v: JSON) in v.string! }
            let ok: Bool
            do {
                if action == .string("choose") {
                    try chooseFolder(folder)
                } else if let a = action["add"]?.array {
                    try addQuery(folder, Query(name: text(a[0]), q: text(a[1]), sort: a[2].string))
                } else if let i = action["remove"]?.int {
                    try removeQuery(folder, at: i)
                } else if let m = action["move"]?.array {
                    try moveQuery(folder, from: m[0].int!, to: m[1].int!)
                } else {
                    let r = action["rename"]!.array!
                    try renameQuery(folder, at: r[0].int!, to: r[1].string!)
                }
                ok = true
            } catch {
                ok = false
            }
            if action != .string("choose") { check(ok == readable, "\(name): ok") }
            let after = try? String(contentsOf: url, encoding: .utf8)
            if c["unchanged"] == .bool(true) || !readable {
                check(after == before, "\(name): unchanged")
            } else if let expect = c["expect"] {
                check(after.map(content) == expect.string.map(content), "\(name): \(after ?? "none")")
            }
        }

        for c in cases["history"]!.array! {
            var history: [String] = []
            for s in c["searches"]!.array! { remember(&history, s.string!) }
            for s in c["forget"]?.array ?? [] { forget(&history, s.string!) }
            check(history == c["expect"]!.array!.map { $0.string! }, "history \(c): \(history)")
        }
    }

    /// Plain text, which the spec leaves to the platform but for what may be left in it
    static func plainText() {
        let cases: [(String, String)] = [
            ("$H\\to\\gamma\\gamma$", "H→γγ"),
            ("The Large $N$ limit", "The Large N limit"),
            ("KC<sup>4</sup> Facility", "KC⁴ Facility"),
            ("95% CL limits & more", "95% CL limits & more"),
            ("costs $5 a month", "costs $5 a month"),
            ("$x^2 + y_{ij}$", "x²+yᵢⱼ"),
            ("AdS$_3$/CFT$_2$", "AdS₃/CFT₂"),
            ("$\\sqrt{s} = 13$ TeV", "√s=13 TeV"),
            ("$t\\bar{t}H$", "tt̄H"),
            ("G\\\"ursey", "Gürsey"),
            ("$\\mathcal{N}=4$ SYM", "N=4 SYM"),
            ("$B^0_s \\to \\mu^+\\mu^-$", "B⁰ₛ→μ⁺μ⁻"),
            ("x &lt; y &amp;&amp; z", "x < y && z"),
            ("$p_T > 20$~GeV", "p_T>20~GeV"),
            ("$\\frac{1}{2}$", "1/2"),
            ("$\\overline{\\rm MS}$", "M̅S̅"),
            ("H<sub>2</sub>O", "H₂O"),
            ("<i>italic</i> text", "italic text"),
            ("$90^\\circ$", "90°"),
            ("$\\left( a \\right.$", "(a"),
            ("\\textit{Ab initio}", "Ab initio"),
            ("100\\% sure", "100% sure"),
        ]
        for (tex, expect) in cases {
            let found = plain(tex)
            check(found == expect, "plain \(tex): \(found)")
            check(!found.contains { "\\{}".contains($0) }, "plain leaves no TeX: \(found)")
        }
    }

    /// Files are read and written as JSON values; unknown keys stay
    static func jsonFiles() {
        let value = try! JSON(parsing: Data(#"{"a":1.0,"b":1.5,"c":[true,null,"x/y"],"d":{"e":10000000000}}"#.utf8))
        check(value["a"] == .int(1) && value["b"] == .double(1.5), "numbers: \(value)")
        check((try? JSON(parsing: value.data())) == value, "round trip")
        let text = String(decoding: try! value.data(), as: UTF8.self)
        check(text.hasSuffix("}\n") && text.contains("x/y"), "written: \(text)")
        check(JSON.object(["a": .string(""), "b": .array([.object([:])]), "c": .int(0)]).pruned == .object(["c": .int(0)]),
              "pruned")
        check(sourceOrder(Data(#"{"v":1,"x":{"sources":{"q":1}},"sources":{"zeta":{"csl":{"a":"}"}},"al\"pha":[1,{}],"m":2}}"#.utf8))
              == ["zeta", "al\"pha", "m"], "source order")
    }

    /// refdir's rules that the cases do not reach (refdir/tests/rules.rs)
    static func refdirRules() {
        let names = ["b", "B", "a", "É", "é", "e", "Z", "A"].sorted(by: namePrecedes)
        check(names == ["A", "a", "B", "b", "e", "Z", "É", "é"], "name order: \(names)")
        let tags = ["topic:b", "z", "a-b:c", "a:c", "A", "topic:A"].sorted(by: tagPrecedes)
        check(tags == ["A", "z", "a:c", "a-b:c", "topic:A", "topic:b"], "tag order: \(tags)")
        check(splitTag("a:b:c") == ("a", "b:c") && splitTag("x").namespace == nil, "split")
        let known = ["Holography", "status:read", "status:reading", "topic:AdS/CFT", "topic:holography", "a", "b", "c", "d", "e", "f"]
        check(suggestions(known, own: ["topic:holography"], text: " HOLO") == ["Holography"], "suggestions by value")
        check(suggestions(known, own: [], text: "status:re") == ["status:read", "status:reading"], "suggestions by tag")
        check(suggestions(known, own: [], text: "") == [], "no suggestions for nothing")
        check(suggestions(Array("abcdefghij").map { "x:\($0)" }, own: [], text: "x").count == suggestionCount, "at most 5")

        let lib = tmpdir("refdir")
        func write(_ name: String, _ text: String) -> URL {
            let dir = lib.appendingPathComponent(name)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try! Data(text.utf8).write(to: dir.appendingPathComponent(entryFile))
            return dir
        }
        _ = write("ok", #"{"v":1}"#)
        _ = write("float", #"{"v":1.0}"#)
        _ = write("v2", #"{"v":2}"#)
        _ = write("string-v", #"{"v":"1"}"#)
        _ = write("array", #"[{"v":1}]"#)
        _ = write(".hidden", #"{"v":1}"#)
        let found = try! RefdirLibrary(lib)
        check(found.entries.map(\.name) == ["float", "ok"] && found.unreadable.count == 3, "entries: \(found.entries.map(\.name))")

        let layered = write("layered", #"{"v":1,"sources":{"zeta":{"csl":{"id":"z","title":"Z","author":[{"family":"A"}]}},"alpha":{"csl":{"id":"a","author":[{"family":"C"}]}}}}"#)
        let e = try! RefdirEntry(layered)
        check(e.id == "a" && e.field("title") == .string("Z"), "layers in key order")
        check(e.field("author") == .array([.object(["family": .string("C")])]), "a later field replaces an earlier whole")

        let dir = write("main", #"{"v":1}"#)
        let entry = try! RefdirEntry(dir)
        check(entry.mainFile() == nil, "no main file")
        for f in [".0-hidden", "b.pdf", "C.pdf", "a.pdf"] { try! Data().write(to: dir.appendingPathComponent(f)) }
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("0-folder"), withIntermediateDirectories: true)
        check(entry.mainFile()?.lastPathComponent == "a.pdf", "main file")
        try! Data().write(to: dir.appendingPathComponent("A.pdf"))
        check(entry.mainFile()?.lastPathComponent == "A.pdf", "main file by code point")

        check(try! freeName(lib, id: "inspire:2990001") == "inspire-2990001", "free name")
        try! FileManager.default.createDirectory(at: lib.appendingPathComponent("maldacena-1997RE"), withIntermediateDirectories: true)
        check(try! freeName(lib, id: "Maldacena:1997re") == "Maldacena-1997re-2", "free name, case")

        let tagged = write("tagged", #"{"v":1,"tags":["a","b","a"]}"#)
        check((try? editTags(tagged) { $0.append("c") }) == ["a", "b", "c"], "repeats removed")
        for bad in [#"{"v":1,"tags":{"a":1}}"#, #"{"v":1,"tags":null}"#] {
            let d = write("bad", bad)
            check((try? editTags(d) { $0.append("x") }) == nil, "tags not written over: \(bad)")
            check(String(decoding: try! Data(contentsOf: d.appendingPathComponent(entryFile)), as: UTF8.self) == bad, "unchanged")
        }
        let leftovers = try! FileManager.default.contentsOfDirectory(atPath: tagged.path)
        check(leftovers == [entryFile], "no temporary files: \(leftovers)")
    }

    static func listRecords() {
        let hit = JSON.object(["id": .string("3227694"), "metadata": .object([
            "control_number": .int(3227694), "titles": .array([.object(["title": .string("AdS$_3$")])]),
            "first_author": .object(["full_name": .string("Iguri, Sergio")]), "author_count": .int(3),
            "citation_count": .int(0)])])
        let r = Record(hit: hit)!
        check(r.recid == 3227694 && r.byline == "S. Iguri et al." && r.citations == 0, "list record: \(r)")
        let search = JSON.object(["hits": .object(["total": .int(9), "hits": .array([hit, .string("odd")])])])
        let parsed = try? parseSearch(search.data())
        check(parsed?.total == 9 && parsed?.records.count == 1, "search")
        check(timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z", "timestamp")
    }
}
#endif
