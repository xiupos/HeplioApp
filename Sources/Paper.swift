// One paper's page, laid out as the App Store lays out an app's: a hero, tiles of details, the
// abstract, the tags of a saved paper, the figures, the authors, and the links

import QuickLook
import SwiftUI

/// The authors listed before Show All
private let authorsShown = 3

struct PaperPage: View {
    let recid: Int
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var record: Record?
    /// The title, abstract, and captions as plain text, made once
    @State private var title = ""
    @State private var abstract = ""
    @State private var captions: [String] = []
    /// The figures loaded so far, by index, drawn over white
    @State private var figures: [Int: UIImage] = [:]
    @State private var error: NetError?
    @State private var missing = false
    @State private var downloading = false
    /// The PDF shown with Quick Look
    @State private var reading: URL?
    @State private var removing = false
    @State private var removingPDF = false
    @State private var editingTags = false
    @State private var sharing: Sharing?
    /// Counts copies, for the feedback
    @State private var copied = 0

    var body: some View {
        Group {
            if let record {
                page(record)
            } else if let error {
                ContentUnavailableView {
                    Label(error.title, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(verbatim: error.message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if missing {
                ContentUnavailableView("Paper Not Found", systemImage: "doc.questionmark",
                                       description: Text("INSPIRE has no record \(String(recid))."))
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let record { toolbar(record) }
        }
        // Once: the page keeps what it loaded while it is open
        .task {
            if record == nil { await load() }
        }
        // One after another; again for those not loaded when the page comes back
        .task(id: record?.recid) { await loadFigures() }
        .quickLookPreview($reading)
        .sensoryFeedback(.success, trigger: copied)
        .sheet(item: $sharing) { sharing in
            ShareSheet(item: sharing.item)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $editingTags) {
            TagEditor(recid: recid)
                .environment(library)
        }
        .confirmationDialog("Remove from Library", isPresented: $removing) {
            Button("Remove Paper", role: .destructive) { library.remove(recid) }
        } message: {
            Text("The paper's folder in the library, with its PDF and any other files in it, will be deleted. This can't be undone.")
        }
        .confirmationDialog("Remove PDF", isPresented: $removingPDF) {
            Button("Remove PDF", role: .destructive) { library.deletePDF(recid) }
        } message: {
            Text("The PDF downloaded from arXiv will be deleted from the library. This can't be undone.")
        }
    }

    // MARK: Loading

    private func load() async {
        error = nil
        do {
            let data = try await Net.get(paperURL(recid))
            let found = try await Task.detached { () -> (Record, String, String, [String])? in
                guard let r = try parseSearch(data).records.first else { return nil }
                return (r, plain(r.title ?? "Untitled"), r.abstract.map(plain) ?? "", r.figures.map { plain($0.caption) })
            }.value
            guard let found else {
                missing = true
                return
            }
            title = found.1
            abstract = found.2
            captions = found.3
            record = found.0
            library.update(found.0)
        } catch is CancellationError {
        } catch {
            self.error = NetError(error)
        }
    }

    private func loadFigures() async {
        guard let record else { return }
        for (i, figure) in record.figures.enumerated() where figures[i] == nil {
            guard let data = try? await Net.get(figure.url) else {
                if Task.isCancelled { return }
                continue
            }
            if let image = UIImage(data: data) { figures[i] = onWhite(image) }
        }
    }

    // MARK: Actions

    /// Downloads the PDF from arXiv into the paper's entry, saving the paper first
    private func getPDF(_ record: Record) async {
        guard let arxiv = record.arxiv else { return }
        if library.paper(recid) == nil {
            guard library.save(record) else { return }
        }
        downloading = true
        defer { downloading = false }
        do {
            let data = try await Net.get(pdfURL(arxiv), session: Net.arxiv)
            try library.keepPDF(recid, data)
        } catch is CancellationError {
        } catch let error as NetError {
            library.error = error.message
        } catch {
            library.error = message(error, "the PDF")
        }
    }

    private func copyBibTeX() async {
        do {
            let data = try await Net.get(bibtexURL(recid))
            UIPasteboard.general.string = String(decoding: data, as: UTF8.self).trimmed
            copied += 1
        } catch is CancellationError {
        } catch {
            library.error = "Could not copy the BibTeX. \(NetError(error).message)"
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        UIPasteboard.general.string = text
        copied += 1
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ record: Record) -> some ToolbarContent {
        let entry = library.paper(recid)
        ToolbarItemGroup(placement: .topBarTrailing) {
            if entry != nil {
                Button("Remove from Library", systemImage: "star.fill") { removing = true }
            } else {
                Button("Save to Library", systemImage: "star") { library.save(record) }
                    .keyboardShortcut("s")
            }
            // Buttons, which open the sheet from the page: a ShareLink in a menu squeezes it into
            // the navigation bar
            Menu("Share", systemImage: "square.and.arrow.up") {
                if let pdf = entry?.pdf {
                    Button("Share PDF", systemImage: "doc.richtext") { sharing = Sharing(item: pdf) }
                }
                if let arxiv = record.arxiv, let url = URL(string: "https://arxiv.org/abs/\(arxiv)") {
                    Button("Share arXiv Link", systemImage: "link") { sharing = Sharing(item: url) }
                }
                if let url = URL(string: "https://inspirehep.net/literature/\(recid)") {
                    Button("Share INSPIRE Link", systemImage: "link") { sharing = Sharing(item: url) }
                }
            }
            Menu("More", systemImage: "ellipsis") {
                Section {
                    Button("Copy BibTeX", systemImage: "doc.on.doc") { Task { await copyBibTeX() } }
                    Button("Copy arXiv ID", systemImage: "number") { copy(record.arxiv) }
                        .disabled(record.arxiv == nil)
                    Button("Copy Citation Key", systemImage: "key") { copy(record.texkey) }
                        .disabled(record.texkey == nil)
                }
                if let entry {
                    Section {
                        if entry.arxivPDF != nil {
                            Button("Remove PDF", systemImage: "minus.circle", role: .destructive) { removingPDF = true }
                        }
                        Button("Remove from Library", systemImage: "trash", role: .destructive) { removing = true }
                    }
                }
            }
        }
    }

    // MARK: The page

    private func page(_ record: Record) -> some View {
        let entry = library.paper(recid)
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero(record, entry)
                    .padding(.horizontal)
                tiles(record)
                if !abstract.isEmpty {
                    Shelf(heading: "Abstract") {
                        Abstract(text: abstract)
                            .padding(.horizontal)
                    }
                }
                if let entry {
                    Shelf(heading: "Tags") {
                        // In the paper's order, each with its count in the library
                        let counts = Dictionary(library.tags.map { ($0.tag, $0.count) }, uniquingKeysWith: max)
                        TagLinks(tags: entry.tags.map { TagCount(tag: $0, count: counts[$0] ?? 1) }, fullNames: true) {
                            Button(entry.tags.isEmpty ? "Add Tags" : "Edit", systemImage: "pencil") { editingTags = true }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                }
                if !record.figures.isEmpty {
                    Shelf(heading: "Figures") { figureRow(record) }
                }
                if !record.authors.isEmpty {
                    Shelf(heading: "Authors") {
                        Separated {
                            ForEach(Array(record.authors.prefix(authorsShown).enumerated()), id: \.offset) { _, author in
                                NavigationLink(value: Route.list(author.list)) {
                                    LinkRow(title: author.fullName, systemImage: "chevron.forward")
                                }
                            }
                            if record.authors.count > authorsShown {
                                NavigationLink(value: Route.authors(record.authors)) {
                                    LinkRow(title: "Show All \(record.authors.count.formatted()) Authors", systemImage: "chevron.forward")
                                }
                            }
                        }
                    }
                }
                if entry?.pdf != nil || record.arxiv != nil || record.doi != nil {
                    Shelf(heading: "Links") { links(record, entry) }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical)
        }
    }

    /// The cover, the title, the authors, the date and journal, and the main button
    private func hero(_ record: Record, _ entry: SavedPaper?) -> some View {
        let names = record.authors.prefix(authorsShown).map(\.short).joined(separator: ", ")
        let byline = names + (record.authorCount > min(record.authors.count, authorsShown) ? " et al." : "")
        let info = [record.date, record.journal].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 16) {
            Cover(pdf: entry?.pdf)
                .frame(width: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title)
                    .font(.title3.bold())
                if !names.isEmpty {
                    Text(verbatim: byline)
                        .foregroundStyle(.secondary)
                }
                if !info.isEmpty {
                    Text(verbatim: info)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                mainButton(record, entry)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Read the PDF in the library, download it there, or read it on arXiv
    private func mainButton(_ record: Record, _ entry: SavedPaper?) -> some View {
        Group {
            if downloading {
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Downloading…")
                    }
                }
                .disabled(true)
            } else if let pdf = entry?.pdf {
                Button("Read") { reading = pdf }
            } else if let arxiv = record.arxiv {
                // Not again over Heplio's PDF, there behind another file
                if library.folder != nil && entry?.arxivPDF == nil {
                    Button("Get PDF") { Task { await getPDF(record) } }
                } else {
                    Button("Read on arXiv") { openURL(URL(string: pdfURL(arxiv))!) }
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    /// The details it has, side by side. Citations and References open their lists
    private func tiles(_ record: Record) -> some View {
        let year = record.date.map { String($0.prefix(4)) }
        let short = record.authors.isEmpty ? "record \(recid)" : record.byline + (year.map { " (\($0))" } ?? "")
        return ScrollView(.horizontal) {
            Separated(axis: .horizontal) {
                if let citations = record.citations {
                    NavigationLink(value: Route.list(Query(name: "Citations of \(short)", q: "refersto:recid:\(recid)", sort: "mostrecent"))) {
                        Tile(label: "Citations", value: citations.formatted(), caption: "Show All", link: true)
                    }
                }
                if let references = record.references {
                    NavigationLink(value: Route.list(Query(name: "References of \(short)", q: "citedby:recid:\(recid)", sort: "mostrecent"))) {
                        Tile(label: "References", value: references.formatted(), caption: "Show All", link: true)
                    }
                }
                if let pages = record.pages {
                    Tile(label: "Length", value: pages.formatted(), caption: pages == 1 ? "page" : "pages")
                }
                if let category = record.category {
                    Tile(label: "arXiv", value: category, caption: record.arxiv ?? "")
                }
                if let p = record.publication {
                    Tile(label: "Journal", value: p.journalTitle ?? "",
                         caption: [p.journalVolume, p.year.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                }
                if let date = record.date {
                    Tile(label: "Date", value: year ?? date, caption: date)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// The figures side by side, each opening its image in the browser
    private func figureRow(_ record: Record) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(record.figures.enumerated()), id: \.offset) { i, figure in
                    Button {
                        if let url = URL(string: figure.url) { openURL(url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Color.white
                                .frame(width: 220, height: 160)
                                .overlay {
                                    if let image = figures[i] {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        ProgressView()
                                            .tint(.gray)
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 8))
                            Text(verbatim: i < captions.count && !captions[i].isEmpty ? captions[i] : "Figure \(i + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(width: 220, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    /// The PDF in the library, arXiv's abstract page and PDF, and the DOI
    private func links(_ record: Record, _ entry: SavedPaper?) -> some View {
        Separated {
            if let pdf = entry?.pdf {
                Button { reading = pdf } label: {
                    LinkRow(title: "PDF in the Library", detail: pdf.lastPathComponent, systemImage: "doc.richtext")
                }
            }
            if let arxiv = record.arxiv {
                Link(destination: URL(string: "https://arxiv.org/abs/\(arxiv)")!) {
                    LinkRow(title: "arXiv", detail: arxiv, systemImage: "arrow.up.forward")
                }
                Link(destination: URL(string: pdfURL(arxiv))!) {
                    LinkRow(title: "PDF on arXiv", detail: pdfURL(arxiv), systemImage: "arrow.up.forward")
                }
            }
            if let doi = record.doi, let url = URL(string: "https://doi.org/\(doi)") {
                Link(destination: url) {
                    LinkRow(title: "DOI", detail: doi, systemImage: "arrow.up.forward")
                }
            }
        }
    }
}

/// The abstract, cut to 6 lines with More while it does not fit them
private struct Abstract: View {
    let text: String
    @State private var expanded = false
    /// The heights of the text as shown, and whole
    @State private var shown: CGFloat = 0
    @State private var whole: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: text)
                .lineLimit(expanded ? nil : 6)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown = $0 }
                .background {
                    Text(verbatim: text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { whole = $0 }
                }
            if !expanded && whole > shown + 1 {
                Button("More") { expanded = true }
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// A detail, as the App Store shows an app's: a label, a value, and a caption under it
private struct Tile: View {
    let label: String
    let value: String
    let caption: String
    var link = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(verbatim: value)
                .font(.title3.bold())
                .lineLimit(1)
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(link ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .frame(minWidth: 96, maxWidth: 180)
        .padding(.horizontal, 12)
        .contentShape(.rect)
    }
}

/// A row that opens something: its title, perhaps a detail under it, and a symbol at its end
private struct LinkRow: View {
    let title: String
    var detail: String?
    let systemImage: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// Edits a saved paper's tags, in a sheet: each is removed by swiping, a field adds one on
/// Return, and rows offer the library's other tags that start with what is typed. The field's
/// text is never changed while the user types in it: an input method's unfinished text would be
/// lost. It is emptied once a tag is added
private struct TagEditor: View {
    let recid: Int
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let tags = library.paper(recid)?.tags ?? []
        NavigationStack {
            Form {
                Section {
                    ForEach(tags, id: \.self) { TagLabel(tag: $0) }
                        .onDelete { offsets in
                            offsets.map { tags[$0] }.forEach { library.detach($0, from: recid) }
                        }
                    TextField("Add Tag", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit {
                            add(text)
                            focused = true
                        }
                    ForEach(suggestions(library.tags.map(\.tag), own: tags, text: text), id: \.self) { tag in
                        Button { add(tag) } label: {
                            Label(tag, systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .showsErrors()
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ tag: String) {
        guard !tag.trimmed.isEmpty else { return }
        library.attach(tag, to: recid)
        text = ""
    }
}

/// What the share sheet shares: a file or a link
private struct Sharing: Identifiable {
    let item: URL
    var id: URL { item }
}

/// The system's share sheet, for what a `ShareLink` cannot be: one opened from a menu's button
private struct ShareSheet: UIViewControllerRepresentable {
    let item: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Draws an image over white: some figures are transparent, and would be unreadable on a dark page
func onWhite(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: image.size))
        image.draw(at: .zero)
    }
}
