// The app: the list's state (`Store`), the saved queries, the places, the list and its pages,
// copying, and PDFs in Quick Look

import QuickLook
import SwiftUI

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
            if let query { place = saved.contains(query) ? .saved(query) : .inspire }
        }
    }
    /// The order of a search: the query shown's
    private(set) var sort: String {
        didSet { UserDefaults.standard.set(sort, forKey: "sort") }
    }
    /// The sidebar's selection. A saved query chosen is shown; INSPIRE leaves the search shown,
    /// unless that is a saved query
    var place: Place? = .inspire {
        didSet {
            switch place {
            case .saved(let q) where q != query: show(q)
            case .inspire where isSaved: clear()
            default: break
            }
        }
    }
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
    /// The PDF in Quick Look, and the paper whose PDF is being downloaded to show
    var reading: URL?
    private(set) var downloading: Int?
    var problem: String?

    init() {
        let stored = UserDefaults.standard.array(forKey: "queries") as? [[String]]
        saved = stored?.compactMap { $0.count == 2 ? Query(q: $0[0], sort: $0[1]) : nil } ?? firstSaved
        sort = UserDefaults.standard.string(forKey: "sort") ?? "mostrecent"
        try? FileManager.default.removeItem(at: Store.pdfs)
    }

    var isSaved: Bool { query.map(saved.contains) ?? false }

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
        place = saved.contains(query) ? .saved(query) : .inspire
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
            let made = await Task.detached { records.map(Paper.init) }.value
            guard n == searchNumber else { return }
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
        guard let arxiv = record.arxiv else { return }
        let file = Store.pdfs.appendingPathComponent(pdfName(arxiv))
        if FileManager.default.fileExists(atPath: file.path) {
            reading = file
            return
        }
        downloading = record.recid
        Task {
            do {
                let data = try await Fetch.pdf(arxiv)
                try FileManager.default.createDirectory(at: Store.pdfs, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                if downloading == record.recid { reading = file }
            } catch {
                problem = error.localizedDescription
            }
            if downloading == record.recid { downloading = nil }
        }
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
        .quickLookPreview($store.reading)
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
        List(selection: $store.place) {
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
                        PaperRow(paper: paper)
                            .tag(paper.id)
                            .contextMenu { PaperMenu(record: paper.record) }
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
            }
        }
    }
}

/// What a paper's long press, in the list, offers
struct PaperMenu: View {
    @Environment(Store.self) private var store
    let record: Record

    var body: some View {
        if record.texkey != nil {
            Button("Copy Key", systemImage: "doc.on.doc") { store.copyKey(record) }
        }
        Button("Copy BibTeX", systemImage: "doc.on.clipboard") {
            Task { await store.copyBibtex(record) }
        }
        if let arxiv = record.arxivURL {
            Button("Read PDF", systemImage: "book") { store.read(record) }
            Link(destination: arxiv) { Label("Open on arXiv", systemImage: "safari") }
        }
        Link(destination: record.url) { Label("Open on INSPIRE", systemImage: "safari") }
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
