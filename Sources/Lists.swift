// Fetching from INSPIRE and arXiv, the lists of a query's papers, a page at a time, and the
// INSPIRE tab

import SwiftUI

// MARK: - Fetching

/// Why a request failed. A 429 is told apart from the rest
enum NetError: Error, Equatable {
    /// The host is limiting requests
    case rateLimited(String)
    case other(String)

    init(_ error: Error) {
        self = error as? NetError ?? .other(error.localizedDescription)
    }

    var title: String {
        switch self {
        case .rateLimited: "Too Many Requests"
        case .other: "Could Not Load"
        }
    }

    var message: String {
        switch self {
        case .rateLimited(let host): "\(host) is limiting requests. Wait a few seconds, then try again."
        case .other(let message): message
        }
    }
}

/// GET requests. Nothing is cached: one session for INSPIRE, which gives a request 30 seconds, and
/// one for arXiv's PDFs, which gives one 5 minutes
enum Net {
    static let inspire = session(seconds: 30)
    static let arxiv = session(seconds: 300)

    private static func session(seconds: Double) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = seconds
        config.timeoutIntervalForResource = seconds
        config.httpAdditionalHeaders = ["User-Agent": "Heplio/\(appVersion) (https://github.com/xiupos/HeplioApp)"]
        return URLSession(configuration: config)
    }

    /// The body of the response. Errors name the host. Cancelled, it throws `CancellationError`
    static func get(_ address: String, session: URLSession = inspire) async throws -> Data {
        guard let url = URL(string: address) else { throw NetError.other("The address is not valid.") }
        let host = url.host().map { $0.hasPrefix("inspirehep") ? "INSPIRE" : $0.hasSuffix("arxiv.org") ? "arXiv" : $0 } ?? address
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetError.other("\(host) cannot be reached. Check the connection.")
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw NetError.rateLimited(host) }
            guard (200..<300).contains(http.statusCode) else {
                throw NetError.other("\(host) answered with error \(http.statusCode).")
            }
        }
        return data
    }
}

// MARK: - Lists

/// A paper of a list, with its title and the start of its abstract as plain text, made once
struct ListRow: Identifiable, Hashable {
    let record: Record
    let title: String
    let abstract: String
    var id: Int { record.recid }

    init(_ record: Record) {
        self.record = record
        title = plain(record.title ?? "Untitled")
        // One line is shown: the start is enough
        abstract = record.abstract.map { plain(String($0.prefix(400))) } ?? ""
    }
}

/// A pushed list: the papers of a query, under its name
struct ListPage: View {
    let query: Query

    var body: some View {
        PaperList(query: query)
            .navigationTitle(query.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The papers of a query, 25 at a time: the next page loads when the end is reached. The user
/// can change the sort, and save the query. Make one anew (`.id`) for another query
struct PaperList: View {
    let query: Query
    @Environment(Library.self) private var library
    @State private var sort: String?
    @State private var rows: [ListRow] = []
    @State private var total: Int?
    /// The last page loaded
    @State private var page = 0
    @State private var error: NetError?
    /// The page loading, if one is. Changing the sort cancels it
    @State private var loading: Task<Void, Never>?

    init(query: Query) {
        self.query = query
        _sort = State(initialValue: query.sort)
    }

    var body: some View {
        List {
            if let total, !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        NavigationLink(value: Route.paper(row.id)) {
                            PaperRow(row: row, saved: library.saved.contains(row.id))
                        }
                        .onAppear {
                            if row.id == rows.last?.id { load(first: false) }
                        }
                    }
                } header: {
                    Text(total == 1 ? "1 result" : "\(total.formatted()) results")
                }
                if loading != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else if let error {
                    VStack(spacing: 8) {
                        Text(verbatim: error.message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { load(first: false) }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if rows.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label(error.title, systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(verbatim: error.message)
                    } actions: {
                        Button("Try Again") { load(first: true) }
                    }
                } else if total == 0 {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                                           description: Text("Nothing on INSPIRE matches this query."))
                } else {
                    ProgressView()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                saveButton
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: $sort) {
                        ForEach(sorts, id: \.self) { Text($0.name).tag($0.sort) }
                    }
                }
            }
        }
        // Not again when the list comes back into view: it keeps what it loaded
        .onAppear {
            if total == nil && loading == nil && error == nil { load(first: true) }
        }
        .onChange(of: sort) { load(first: true) }
    }

    /// Saves the query with the sort shown; filled once it is saved
    @ViewBuilder
    private var saveButton: some View {
        let saving = Query(name: query.name, q: query.q, sort: sort)
        if library.isSaved(saving) {
            Button("Query Saved", systemImage: "bookmark.fill") {}
                .disabled(true)
        } else {
            Button("Save Query", systemImage: "bookmark") { library.saveQuery(saving) }
                .disabled(!library.canSaveQueries)
        }
    }

    /// Loads the first page, in place of what is shown, or else the next one, if there is one and
    /// none is loading
    private func load(first: Bool) {
        if first {
            loading?.cancel()
            rows = []
            total = nil
            page = 0
        } else {
            guard loading == nil, let total, hasMore(total: total, page: page) else { return }
        }
        error = nil
        let (q, sort, next) = (query.q, sort, page + 1)
        loading = Task {
            do {
                let data = try await Net.get(listURL(q, sort: sort, page: next))
                let (count, found) = try await Task.detached {
                    let (count, records) = try parseSearch(data)
                    return (count, records.map(ListRow.init))
                }.value
                try Task.checkCancellation()
                // A paper that moved to the next page while paging is not listed twice
                let listed = Set(rows.map(\.id))
                rows += found.filter { !listed.contains($0.id) }
                total = count
                page = next
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = NetError(error)
            }
            loading = nil
        }
    }
}

/// A paper in a list: its title, first author, date, and citations, and the start of its
/// abstract; its kind, unless it is an article, and a star if it is saved
struct PaperRow: View {
    let row: ListRow
    let saved: Bool

    var body: some View {
        let r = row.record
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: row.title)
                .font(.headline)
                .lineLimit(3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: [r.byline, r.date ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let kind = r.documentType, kind != "article" {
                    Text(verbatim: kind)
                        .font(.caption)
                        .lineLimit(1)
                }
                if saved {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Saved")
                }
                if let citations = r.citations {
                    Text("\(Image(systemName: "quote.opening")) \(citations.formatted())")
                        .monospacedDigit()
                        .accessibilityLabel(citations == 1 ? "1 citation" : "\(citations) citations")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !row.abstract.isEmpty {
                Text(verbatim: row.abstract)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// All the authors of a paper, each opening their papers
struct AuthorsPage: View {
    let authors: [Author]

    var body: some View {
        List(Array(authors.enumerated()), id: \.offset) { _, author in
            NavigationLink(value: Route.list(author.list)) {
                Text(verbatim: author.fullName)
            }
        }
        .navigationTitle("\(authors.count.formatted()) Authors")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Author {
    /// The author's papers, newest first, under their short name
    var list: Query {
        Query(name: short, q: query, sort: "mostrecent")
    }
}

// MARK: - INSPIRE

/// The INSPIRE tab: a field that searches on Return, and, while it is empty, the saved queries and
/// the recent searches, or examples of the syntax while there are none. A search's list shows in
/// place of them until the field is emptied
struct InspirePage: View {
    @Environment(Library.self) private var library
    @State private var text = ""
    /// The search shown, and a count that lists it again when it is searched again
    @State private var searched: (query: Query, count: Int)?
    @State private var renaming: (index: Int, query: Query)?
    @State private var newName = ""

    private static let tips = URL(string: "https://help.inspirehep.net/knowledge-base/inspire-paper-search/")!
    private static let examples = ["a Juan.M.Maldacena.1", "t black hole and topcite 100+", "refersto:recid:451647",
                                   "arxiv_eprints.categories:hep-th and de > today - 7"]

    var body: some View {
        Group {
            if let searched {
                PaperList(query: searched.query)
                    .id(searched.count)
            } else {
                home
            }
        }
        .navigationTitle("INSPIRE")
        .toolbarTitleDisplayMode(.inlineLarge)
        // Always shown: searching is what the tab is for
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search INSPIRE")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { search() }
        .onChange(of: text) { _, text in
            if text.isEmpty { searched = nil }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: Self.tips) {
                    Label("Search Tips", systemImage: "questionmark.circle")
                }
            }
        }
        .settingsButton()
        .alert("Rename Query", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renaming { library.rename(renaming.query, at: renaming.index, to: newName) }
            }
        }
    }

    /// Searches for the field's text, trimmed, and remembers it
    private func search() {
        let text = text.trimmed
        guard !text.isEmpty else { return }
        library.addToHistory(text)
        searched = (Query(name: text, q: text, sort: nil), (searched?.count ?? 0) + 1)
    }

    /// Shows a search again, as if typed
    private func run(_ text: String) {
        self.text = text
        search()
    }

    private var home: some View {
        List {
            Section {
                switch library.queries {
                case .unreadable:
                    Label("The saved queries can't be read. Fix or remove .heplio/queries.json in the library folder.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                case .list(let list) where !list.isEmpty:
                    ForEach(Array(list.enumerated()), id: \.offset) { index, query in
                        NavigationLink(value: Route.list(query)) {
                            Label(query.name, systemImage: "bookmark")
                        }
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") {
                                newName = query.name
                                renaming = (index, query)
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                library.deleteQuery(query, at: index)
                            }
                        }
                    }
                    .onMove { from, to in
                        guard let from = from.first else { return }
                        library.reorderQuery(list[from], from: from, to: to > from ? to - 1 : to)
                    }
                    .onDelete { offsets in
                        if let index = offsets.first { library.deleteQuery(list[index], at: index) }
                    }
                default:
                    Text(library.folder == nil ? "Choose a library folder in Settings to save queries."
                                               : "Save a query from a search or any list.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                // Here, not in the toolbar, where on an iPad it is folded into a menu beside the
                // tab bar
                HStack {
                    Text("Saved Queries")
                    Spacer()
                    if !library.queries.list.isEmpty { EditButton() }
                }
            }
            Section {
                if library.history.isEmpty {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { run(example) } label: {
                            Label {
                                Text(verbatim: example)
                                    .foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                } else {
                    ForEach(library.history, id: \.self) { recent in
                        Button { run(recent) } label: {
                            Label {
                                Text(verbatim: recent)
                                    .foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { library.history[$0] }.forEach(library.removeFromHistory)
                    }
                }
            } header: {
                Text(library.history.isEmpty ? "Examples" : "Recent Searches")
            }
        }
    }
}
