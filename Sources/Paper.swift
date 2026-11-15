// One paper, as INSPIRE has it: its title, authors, abstract, details, and the lists it opens, its
// citations, references, and each author's papers. Its key is what the user copies, to add it to
// a library with Refdir

import SwiftUI

/// Authors shown before the link to the rest on INSPIRE
private let shownAuthors = 10

struct PaperPage: View {
    @Environment(Store.self) private var store
    /// The list's record: only its first author, and no details, until the whole one is in
    let start: Record
    @State private var full: Record?
    @State private var loading = true
    /// What was copied last: shown on its button
    @State private var copied: String?

    private var paper: Record { full ?? start }

    var body: some View {
        let r = paper
        List {
            Section {
                heading
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            let lists = listRows(r)
            if !lists.isEmpty {
                Section {
                    ForEach(lists) { row($0) }
                }
            }
            if let abstract = r.abstract {
                Section("Abstract") {
                    Text(plain(abstract))
                        .textSelection(.enabled)
                }
            }
            Section("Details") {
                ForEach(details(r)) { row($0) }
            }
            // Only once the whole record is in: the list's has only the first author
            let authors = full == nil ? [] : authorRows(r)
            if !authors.isEmpty {
                Section("Authors") {
                    ForEach(authors) { row($0) }
                }
            }
        }
        // Made again, not changed, when the whole record is in: changed, with rows added in every
        // section at once, the list drew some rows in the wrong places, and left one empty
        .id(full == nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loading {
                ToolbarItem(placement: .primaryAction) { ProgressView() }
            }
        }
        .task {
            do {
                full = try await Fetch.paper(start.recid)
            } catch {
                store.problem = error.localizedDescription
            }
            loading = false
        }
    }

    /// The title, the names, its date, journal, and arXiv number, and what can be done with it
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plain(paper.title))
                .font(.title2.bold())
                .textSelection(.enabled)
            Text(names)
            Text([paper.date, paper.journals.first, paper.arxiv].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            // On one line where they fit, else on two
            ViewThatFits {
                HStack {
                    copyButtons
                    pdfButton
                    inspireLink
                }
                VStack(alignment: .leading) {
                    HStack { copyButtons }
                    HStack {
                        pdfButton
                        inspireLink
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private var copyButtons: some View {
        if paper.texkey != nil {
            Button(copied == "key" ? "Copied" : "Copy Key") {
                store.copyKey(paper)
                copied = "key"
            }
            .buttonStyle(.borderedProminent)
        }
        Button(copied == "bibtex" ? "Copied" : "Copy BibTeX") {
            Task {
                await store.copyBibtex(paper)
                copied = "bibtex"
            }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var pdfButton: some View {
        if paper.arxiv != nil {
            let downloading = store.downloading == paper.recid
            Button(downloading ? "Downloading…" : "PDF") { store.read(paper) }
                .buttonStyle(.bordered)
                .disabled(downloading)
        }
    }

    private var inspireLink: some View {
        Link("INSPIRE", destination: paper.url)
            .buttonStyle(.bordered)
    }

    /// Ten short names, then how many more, after a collaboration's byline
    private var names: String {
        let names = paper.authors.prefix(shownAuthors).map { shortName($0.fullName) }
        let more = paper.authorCount - names.count
        let line = names.joined(separator: ", ") + (more > 0 ? " and \(count(more)) more" : "")
        return paper.collaborations.isEmpty ? line : "\(paper.byline) · \(line)"
    }

    /// A row of the details or the authors: one kind of row, from data, each there, as a section of
    /// rows made by `if`s and several `ForEach`es was drawn with rows missing and one left empty
    private struct Row: Identifiable {
        let id: String
        let title: String
        var value = ""
        /// Opens a list of INSPIRE's in the list's column
        var query: String?
        var link: URL?
    }

    /// Its citations and references
    private func listRows(_ r: Record) -> [Row] {
        var rows: [Row] = []
        if let n = r.citations {
            let without = r.citationsWithoutSelf.map { " · \(count($0)) without self-citations" } ?? ""
            rows.append(Row(id: "citations", title: "Citations", value: "\(count(n))\(without)", query: r.citationsQuery))
        }
        if let n = r.references {
            rows.append(Row(id: "references", title: "References", value: count(n), query: r.referencesQuery))
        }
        return rows
    }

    private func details(_ r: Record) -> [Row] {
        var rows: [Row] = []
        func add(_ title: String, _ value: String?, link: URL? = nil) {
            if let value, !value.isEmpty {
                rows.append(Row(id: "\(rows.count)", title: title, value: value, link: link))
            }
        }
        add("Key", r.texkey)
        add("Date", r.date)
        r.journals.forEach { add("Journal", $0) }
        if let arxiv = r.arxiv {
            let categories = r.categories.isEmpty ? "" : " [\(r.categories.joined(separator: ", "))]"
            add("arXiv", arxiv + categories, link: r.arxivURL)
        }
        r.dois.forEach { add("DOI", $0, link: URL(string: "https://doi.org/\($0)")) }
        add("Report Numbers", r.reportNumbers.joined(separator: ", "))
        add("Pages", r.pages.map { "\($0)" })
        add("Type", r.documentTypes.joined(separator: ", "))
        add("Keywords", r.keywords.joined(separator: ", "))
        return rows
    }

    /// Each collaboration, the first authors, then how many more on INSPIRE
    private func authorRows(_ r: Record) -> [Row] {
        var rows = r.collaborations.enumerated().map { i, c in
            Row(id: "c\(i)", title: c, value: "Collaboration", query: "cn \"\(c)\"")
        }
        rows += r.authors.prefix(shownAuthors).enumerated().map { i, a in
            Row(id: "a\(i)", title: a.fullName, value: a.affiliations.joined(separator: "; "), query: a.query)
        }
        if r.authorCount > shownAuthors && r.authors.count > 1 {
            rows.append(Row(id: "more", title: "\(count(r.authorCount - shownAuthors)) more on INSPIRE", link: r.url))
        }
        return rows
    }

    @ViewBuilder
    private func row(_ row: Row) -> some View {
        if let q = row.query {
            Button {
                store.open(q)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .foregroundStyle(.primary)
                    if !row.value.isEmpty {
                        Text(row.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let url = row.link {
            Link(destination: url) {
                if row.value.isEmpty { Text(row.title) } else { LabeledContent(row.title, value: row.value) }
            }
        } else {
            LabeledContent(row.title) {
                Text(row.value)
                    .textSelection(.enabled)
            }
        }
    }
}
