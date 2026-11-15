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
            if r.citations != nil || r.references != nil {
                Section {
                    if let n = r.citations {
                        let without = r.citationsWithoutSelf.map { " · \(count($0)) without self-citations" } ?? ""
                        opening("Citations", "\(count(n))\(without)", r.citationsQuery)
                    }
                    if let n = r.references {
                        opening("References", count(n), r.referencesQuery)
                    }
                }
            }
            if let abstract = r.abstract {
                Section("Abstract") {
                    Text(plain(abstract))
                        .textSelection(.enabled)
                }
            }
            Section("Details") {
                detail("Key", r.texkey)
                detail("Date", r.date)
                ForEach(r.journals, id: \.self) { detail("Journal", $0) }
                if let arxiv = r.arxiv, let url = r.arxivURL {
                    let categories = r.categories.isEmpty ? "" : " [\(r.categories.joined(separator: ", "))]"
                    Link(destination: url) { LabeledContent("arXiv", value: arxiv + categories) }
                }
                ForEach(r.dois, id: \.self) { doi in
                    if let url = URL(string: "https://doi.org/\(doi)") {
                        Link(destination: url) { LabeledContent("DOI", value: doi) }
                    }
                }
                detail("Report Numbers", r.reportNumbers.joined(separator: ", "))
                detail("Pages", r.pages.map { "\($0)" })
                detail("Type", r.documentTypes.joined(separator: ", "))
                detail("Keywords", r.keywords.joined(separator: ", "))
            }
            // Only once the whole record is in: the list's has only the first author
            if full != nil && (!r.authors.isEmpty || !r.collaborations.isEmpty) {
                Section("Authors") {
                    // By place, not by value: an author is the same row whatever it shows
                    ForEach(Array(r.collaborations.enumerated()), id: \.offset) { _, c in
                        opening(c, "Collaboration", "cn \"\(c)\"")
                    }
                    ForEach(Array(r.authors.prefix(shownAuthors).enumerated()), id: \.offset) { _, a in
                        opening(a.fullName, a.affiliations.joined(separator: "; "), a.query)
                    }
                    if r.authorCount > shownAuthors && r.authors.count > 1 {
                        Link("\(count(r.authorCount - shownAuthors)) more on INSPIRE", destination: r.url)
                    }
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

    /// A row that shows a list of INSPIRE's in the list's column
    private func opening(_ title: String, _ value: String, _ q: String) -> some View {
        Button {
            store.open(q)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if !value.isEmpty {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A detail it has, which can be selected and copied
    @ViewBuilder
    private func detail(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }
}
