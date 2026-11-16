// The app: the list's state (`Store`), the saved queries, the places, the list and its pages,
// copying, and PDFs in Quick Look

import PDFKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

@main
struct HeplioApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

// MARK: - The store

/// A paper of the list, with what its row shows, made once, off the main thread
struct Paper: Identifiable, Hashable, Sendable {
    let record: Record
    let title: String
    let subtitle: String
    /// The start: enough for two lines, and quicker to make
    let abstract: String
    var id: Int { record.recid }

    init(_ record: Record) {
        self.record = record
        title = plain(record.title)
        let citations = record.citations.map { counted($0, "citation") }
        subtitle = [record.byline, record.date, citations].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
        abstract = plain(String((record.abstract ?? "").prefix(400)))
    }
}

/// A place of the sidebar
enum Place: Hashable {
    case inspire
    case saved(Query)
}

/// What the list shows
enum ListState: Equatable {
    /// Nothing searched yet
    case start
    case loading
    case failed(String)
    /// The pages loaded, of how many papers in all
    case shown(total: Int, pages: Int)
}

@MainActor
@Observable
final class Store {
    /// The PDFs downloaded to read, of this launch: emptied at the next
    static let pdfs = FileManager.default.temporaryDirectory.appendingPathComponent("PDFs")

    var saved: [Query] {
        didSet {
            UserDefaults.standard.set(saved.map { [$0.q, $0.sort] }, forKey: "queries")
            // The place follows the query shown, saved or not
            if let query { follow(query) }
        }
    }
    /// The order of a search: the query shown's
    private(set) var sort: String {
        didSet { UserDefaults.standard.set(sort, forKey: "sort") }
    }
    /// The sidebar's selection: the saved query shown, else INSPIRE. Setting it does nothing more:
    /// what the user chooses goes through `choose`
    private(set) var place: Place? = .inspire
    private(set) var query: Query?
    private(set) var papers: [Paper] = []
    private(set) var state = ListState.start
    /// Whether the next page is being loaded
    private(set) var loadingMore = false
    /// Each search is numbered, so that an answer to one replaced by another is dropped
    private var searchNumber = 0
    /// The list's selection, and the paper on the page, which stays when the list changes
    var selection: Int? {
        didSet {
            if let paper = papers.first(where: { $0.id == selection }) { self.paper = paper.record }
        }
    }
    private(set) var paper: Record?
    /// The column shown where only one fits, as on an iPhone
    var column = NavigationSplitViewColumn.sidebar
    /// The paper whose PDF Quick Look shows first, and the papers a swipe goes through: the list's
    /// with an arXiv number, or that one alone
    var reading: Int?
    private(set) var readingItems: [Record] = []
    /// The paper whose PDF is being downloaded to show
    private(set) var downloading: Int?
    var problem: String?

    init() {
        let stored = UserDefaults.standard.array(forKey: "queries") as? [[String]]
        saved = stored?.compactMap { $0.count == 2 ? Query(q: $0[0], sort: $0[1]) : nil } ?? firstSaved
        sort = UserDefaults.standard.string(forKey: "sort") ?? "mostrecent"
        try? FileManager.default.removeItem(at: Store.pdfs)
    }

    var isSaved: Bool { query.map(saved.contains) ?? false }

    /// A place the user chose: a saved query is shown; INSPIRE leaves the search shown, unless that
    /// is a saved query
    func choose(_ chosen: Place?) {
        place = chosen
        switch chosen {
        case .saved(let q) where q != query: show(q)
        case .inspire where isSaved: clear()
        default: break
        }
    }

    /// The place of the query shown, set only when it changes
    private func follow(_ query: Query) {
        let new = saved.contains(query) ? Place.saved(query) : .inspire
        if place != new { place = new }
    }

    // MARK: Searching

    /// What was typed into the search field, in the sort chosen
    func search(_ typed: String) {
        let q = inspireQuery(typed)
        if !q.isEmpty { show(Query(q: q, sort: sort)) }
    }

    /// Searches INSPIRE for the query, from its first page
    func show(_ query: Query) {
        self.query = query
        sort = query.sort
        follow(query)
        searchNumber += 1
        papers = []
        loadingMore = false
        state = .loading
        let n = searchNumber
        Task { await load(query, page: 1, search: n) }
    }

    /// A paper's citations, references, or author's papers, by date, in the list
    func open(_ q: String) {
        show(Query(q: q, sort: "mostrecent"))
        selection = nil
        column = .content
    }

    func clear() {
        query = nil
        searchNumber += 1
        papers = []
        state = .start
    }

    func retry() {
        if let query { show(query) }
    }

    /// Another order searches the query shown again
    func setSort(_ new: String) {
        sort = new
        if let query, query.sort != new { show(Query(q: query.q, sort: new)) }
    }

    func toggleSaved() {
        if let query { saved = toggled(saved, query) }
    }

    /// The next page, at the end of the list. One that fails says why, and the list keeps what it
    /// has: reaching its end again tries again
    func more() {
        guard case .shown(let total, let pages) = state, let query, !loadingMore,
              hasMore(total: total, page: pages) else { return }
        loadingMore = true
        let n = searchNumber
        Task { await load(query, page: pages + 1, search: n) }
    }

    private func load(_ query: Query, page: Int, search n: Int) async {
        do {
            let (total, records) = try await Fetch.search(query, page: page)
            guard n == searchNumber else { return }
            let made = records.map(Paper.init)
            // A paper INSPIRE gives again on a later page is not listed twice
            let listed = Set(papers.map(\.id))
            papers += made.filter { !listed.contains($0.id) }
            state = .shown(total: total, pages: page)
        } catch {
            guard n == searchNumber else { return }
            if page == 1 { state = .failed(error.localizedDescription) } else { problem = error.localizedDescription }
        }
        if n == searchNumber { loadingMore = false }
    }

    // MARK: A paper

    func copyKey(_ record: Record) {
        UIPasteboard.general.string = record.texkey
    }

    func copyBibtex(_ record: Record) async {
        do {
            UIPasteboard.general.string = try await Fetch.bibtex(record.recid)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Shows the paper's PDF in Quick Look, downloaded first, unless another is asked for meanwhile
    func read(_ record: Record) {
        guard record.arxiv != nil else { return }
        downloading = record.recid
        Task {
            do {
                _ = try await download(record)
                if downloading == record.recid {
                    let listed = papers.map(\.record).filter { $0.arxiv != nil }
                    readingItems = listed.contains { $0.recid == record.recid } ? listed : [record]
                    reading = record.recid
                }
            } catch {
                problem = error.localizedDescription
            }
            if downloading == record.recid { downloading = nil }
        }
    }

    /// The paper's PDF, if it is downloaded
    func downloaded(_ record: Record) -> URL? {
        guard let arxiv = record.arxiv else { return nil }
        let file = Store.pdfs.appendingPathComponent(pdfName(arxiv))
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The paper's PDF, downloaded from arXiv if it is not yet
    func download(_ record: Record) async throws -> URL {
        if let file = downloaded(record) { return file }
        guard let arxiv = record.arxiv else { throw Failure("It has no PDF on arXiv.") }
        let data = try await Fetch.pdf(arxiv)
        try FileManager.default.createDirectory(at: Store.pdfs, withIntermediateDirectories: true)
        let file = Store.pdfs.appendingPathComponent(pdfName(arxiv))
        try data.write(to: file, options: .atomic)
        return file
    }
}

// MARK: - The views

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(preferredCompactColumn: $store.column) {
            Places()
        } content: {
            PaperList()
        } detail: {
            if let paper = store.paper {
                // A page for each paper, which loads its details
                PaperPage(start: paper).id(paper.recid)
            } else {
                ContentUnavailableView("No Paper Selected", systemImage: "doc.text")
            }
        }
        // Read here, so that a change of it updates the reader
        .background { PDFReader(store: store, reading: store.reading) }
        .alert("Heplio", isPresented: Binding { store.problem != nil } set: { if !$0 { store.problem = nil } }) {
            Button("OK") {}
        } message: {
            Text(store.problem ?? "")
        }
    }
}

/// INSPIRE, then the saved queries
private struct Places: View {
    @Environment(Store.self) private var store
    @State private var showingAbout = false

    var body: some View {
        @Bindable var store = store
        List(selection: Binding { store.place } set: { store.choose($0) }) {
            Label("INSPIRE", systemImage: "magnifyingglass")
                .tag(Place.inspire)
            if !store.saved.isEmpty {
                Section("Saved") {
                    ForEach(store.saved, id: \.self) { query in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(query.q)
                                .lineLimit(2)
                            Text(sortName(query.sort))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Place.saved(query))
                        .contextMenu {
                            Button("Copy Query", systemImage: "doc.on.doc") { UIPasteboard.general.string = query.q }
                            Link(destination: query.url) { Label("Open on INSPIRE", systemImage: "safari") }
                            Button("Remove", systemImage: "star.slash", role: .destructive) {
                                store.saved = toggled(store.saved, query)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "star.slash") { store.saved = toggled(store.saved, query) }
                                .tint(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Heplio")
        .toolbar {
            Menu {
                Link(destination: searchTips) { Label("Search Tips", systemImage: "questionmark.circle") }
                Button("About Heplio", systemImage: "info.circle") { showingAbout = true }
            } label: {
                Label("Menu", systemImage: "ellipsis.circle")
            }
        }
        .alert("Heplio", isPresented: $showingAbout) {
            Button("OK") {}
        } message: {
            Text("A search of INSPIRE-HEP. Copy a paper's key, and add it to your library with Refdir.\nHeplio is not affiliated with INSPIRE.")
        }
    }
}

/// The query's papers, a page at a time
private struct PaperList: View {
    @Environment(Store.self) private var store
    @State private var text = ""

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            if case .shown(let total, _) = store.state, total > 0 {
                Section {
                    ForEach(store.papers) { paper in
                        Group {
                            // With an arXiv number, its PDF's first page over the menu, as
                            // refdir's rows show theirs
                            if paper.record.arxiv != nil {
                                PaperRow(paper: paper)
                                    .contextMenu { PaperMenu(record: paper.record) } preview: {
                                        FirstPage(store: store, record: paper.record)
                                    }
                            } else {
                                PaperRow(paper: paper).contextMenu { PaperMenu(record: paper.record) }
                            }
                        }
                        .tag(paper.id)
                        // Only to the left: a swipe to the right goes back to the places
                        .swipeActions(edge: .trailing) {
                            if paper.record.texkey != nil {
                                Button("Copy Key", systemImage: "doc.on.doc") { store.copyKey(paper.record) }
                                    .tint(.orange)
                            }
                        }
                        .onAppear {
                            if paper.id == store.papers.last?.id { store.more() }
                        }
                    }
                    if store.loadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text(counted(total, "result"))
                }
            }
        }
        .overlay {
            switch store.state {
            case .start:
                ContentUnavailableView {
                    Label("Search INSPIRE", systemImage: "magnifyingglass")
                } description: {
                    Text("By title, author, arXiv number, DOI, texkey, or link, in INSPIRE's [search syntax](https://help.inspirehep.net/knowledge-base/inspire-paper-search/)")
                }
            case .loading:
                ProgressView()
            case .failed(let why):
                ContentUnavailableView {
                    Label("Could Not Search", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(why)
                } actions: {
                    Button("Try Again") { store.retry() }
                        .buttonStyle(.bordered)
                }
            case .shown(0, _):
                ContentUnavailableView.search(text: store.query?.q ?? "")
            case .shown:
                EmptyView()
            }
        }
        .searchable(text: $text, prompt: "Search INSPIRE")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { store.search(text) }
        // The field shows the query shown: a paper's citations, a saved query
        .onChange(of: store.query) { text = store.query?.q ?? text }
        .refreshable { store.retry() }
        .navigationTitle("INSPIRE")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(store.isSaved ? "Remove Saved Query" : "Save Query",
                       systemImage: store.isSaved ? "star.fill" : "star") { store.toggleSaved() }
                    .disabled(store.query == nil)
                Menu {
                    Picker("Sort", selection: Binding { store.sort } set: { store.setSort($0) }) {
                        ForEach(sorts, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                if let query = store.query, case .shown(let total, let pages) = store.state, total > 0 {
                    ShareLink(item: ListBib(query: query, pages: pages),
                              preview: SharePreview("\(ListBib.name(query)).bib")) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Export", systemImage: "square.and.arrow.up") {}
                        .disabled(true)
                }
            }
        }
    }
}

/// The BibTeX of the list's pages loaded, as a file to share, asked for of INSPIRE when shared:
/// a page at a time, 350 ms apart, as INSPIRE allows about 15 requests in 5 seconds
struct ListBib: Transferable {
    let query: Query
    let pages: Int

    static func name(_ query: Query) -> String {
        String(query.q.replacingOccurrences(of: "/", with: "-").prefix(60))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "bib") ?? .plainText) { list in
            var entries: [String] = []
            for page in 1...max(list.pages, 1) {
                if page > 1 { try await Task.sleep(nanoseconds: 350_000_000) }
                entries.append(try await Fetch.listBibtex(list.query, page: page))
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name(list.query)).bib")
            try Data((entries.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n").utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

/// What a paper's long press, in the list, offers: in refdir's order, the PDF first, then
/// copying, then the links
struct PaperMenu: View {
    @Environment(Store.self) private var store
    let record: Record

    var body: some View {
        if record.arxiv != nil {
            Button("Read", systemImage: "book") { store.read(record) }
        }
        ShareLink(item: record.url, subject: Text(plain(record.title))) {
            Label("Share Link", systemImage: "square.and.arrow.up")
        }
        if record.texkey != nil {
            Button("Copy Key", systemImage: "doc.on.doc") { store.copyKey(record) }
        }
        Button("Copy BibTeX", systemImage: "doc.on.clipboard") {
            Task { await store.copyBibtex(record) }
        }
        Link(destination: record.url) { Label("Open on INSPIRE", systemImage: "safari") }
        if let arxiv = record.arxivURL {
            Link(destination: arxiv) { Label("Open on arXiv", systemImage: "safari") }
        }
    }
}

/// A paper's PDF's first page, over its menu, as refdir's rows show theirs: downloaded when the
/// menu shows it, and kept, so that Read then shows it at once. Its size is fixed, so that the
/// preview does not jump when the page comes
private struct FirstPage: View {
    let store: Store
    let record: Record
    @State private var page: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let page {
                Image(uiImage: page)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Image(systemName: "doc.richtext")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 300, height: 400)
        .task {
            if let url = try? await store.download(record) {
                page = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
            }
            failed = page == nil
        }
    }
}

private struct PaperRow: View {
    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(paper.title)
                .lineLimit(3)
            Text(paper.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !paper.abstract.isEmpty {
                Text(paper.abstract)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }
}

/// Quick Look over the list's PDFs, from the paper read, so that a swipe goes on to the one before
/// or after. It is presented from UIKit: `quickLookPreview` takes files only, and these are
/// downloaded as they are shown. The one shown and its neighbours are downloaded; one shown before
/// its PDF was in says so in its title, and is shown again once it is in
struct PDFReader: UIViewControllerRepresentable {
    let store: Store
    let reading: Int?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        guard let recid = reading, host.presentedViewController == nil else { return }
        coordinator.items = store.readingItems
        let preview = QLPreviewController()
        preview.dataSource = coordinator
        preview.delegate = coordinator
        preview.currentPreviewItemIndex = coordinator.items.firstIndex { $0.recid == recid } ?? 0
        coordinator.start(preview)
        host.present(preview, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store)
    }

    /// An item whose PDF is not in: its title says why
    final class Waiting: NSObject, QLPreviewItem {
        let previewItemTitle: String?
        var previewItemURL: URL? { nil }

        init(_ title: String) {
            previewItemTitle = title
        }
    }

    // Quick Look calls these on the main thread, though its protocols do not say so
    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource,
                             @preconcurrency QLPreviewControllerDelegate {
        var store: Store
        var items: [Record] = []
        private weak var controller: QLPreviewController?
        /// The items shown waiting for their PDF, by index
        private var waiting: Set<Int> = []
        /// The downloads started, and those that failed, by recid
        private var started: Set<Int> = []
        private var failures: [Int: String] = [:]
        private var timer: Timer?

        init(_ store: Store) {
            self.store = store
        }

        func start(_ controller: QLPreviewController) {
            self.controller = controller
            waiting = []
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }

        /// Quick Look tells no swipe: the item shown is looked at twice a second. Its neighbours
        /// are downloaded, and it is shown again if it was waiting and its PDF, or why not, is in
        private func tick() {
            guard let controller else { return }
            let i = controller.currentPreviewItemIndex
            for j in [i, i + 1, i - 1] where items.indices.contains(j) { load(items[j]) }
            guard waiting.contains(i), items.indices.contains(i) else { return }
            let r = items[i]
            if store.downloaded(r) != nil || failures[r.recid] != nil {
                waiting.remove(i)
                controller.refreshCurrentPreviewItem()
            }
        }

        private func load(_ r: Record) {
            guard store.downloaded(r) == nil, !started.contains(r.recid) else { return }
            started.insert(r.recid)
            Task {
                do {
                    _ = try await store.download(r)
                } catch {
                    failures[r.recid] = error.localizedDescription
                }
            }
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            items.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            let r = items[index]
            if let file = store.downloaded(r) { return file as NSURL }
            if let why = failures[r.recid] { return Waiting("No PDF: \(why)") }
            waiting.insert(index)
            load(r)
            return Waiting("Downloading…")
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            timer?.invalidate()
            timer = nil
            items = []
            store.reading = nil
        }
    }
}
