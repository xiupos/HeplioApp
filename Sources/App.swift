// The app: the library's state (`Library`), the folder and its bookmark, the tabs, navigation,
// and settings

import SwiftUI
import UniformTypeIdentifiers

@main
struct HeplioApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}

// MARK: - Library

/// A tag of the library, and the number of its papers
struct TagCount: Hashable, Identifiable {
    let tag: String
    let count: Int
    var id: String { tag }
}

/// The library folder, as last read, and the search history. One for the app. Every change to
/// the folder reads it again after, off the main thread
@MainActor
@Observable
final class Library {
    /// The chosen folder, while the app has access to it
    private(set) var folder: URL?
    /// Newest `added` first, then by folder name
    private(set) var papers: [SavedPaper] = []
    /// The recids of the papers
    private(set) var saved: Set<Int> = []
    private(set) var tags: [TagCount] = []
    private(set) var queries: Queries = .missing
    /// Newest first
    private(set) var history: [String]
    /// Shown in an alert
    var error: String?
    /// Whether the folder picker is shown
    var choosingFolder = false

    private let defaults = UserDefaults.standard
    /// Counts the reads begun: one overtaken by a newer one is dropped
    private var started = 0

    init() {
        history = defaults.stringArray(forKey: "history") ?? []
        guard let bookmark = defaults.data(forKey: "folder") else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) {
            open(url, remember: stale)
            refresh()
        } else {
            error = "The library folder could not be found. Choose it again in Settings."
        }
    }

    /// Opens a folder the user chose, in place of the current one. A new library gets an example
    /// query
    func choose(_ url: URL) {
        folder?.stopAccessingSecurityScopedResource()
        papers = []
        saved = []
        tags = []
        queries = .missing
        open(url, remember: true)
        change("the saved queries", chooseFolder)
    }

    private func open(_ url: URL, remember: Bool) {
        // false for folders the app may read anyway, such as its own
        _ = url.startAccessingSecurityScopedResource()
        folder = url
        if remember, let bookmark = try? url.bookmarkData() {
            defaults.set(bookmark, forKey: "folder")
        }
    }

    /// Changes the folder, says why if that fails, and reads it again
    private func change(_ what: String, _ change: (URL) throws -> Void) {
        guard let folder else { return }
        do {
            try change(folder)
        } catch {
            self.error = message(error, what)
        }
        refresh()
    }

    /// Reads the folder again
    func reload() async {
        guard let folder else { return }
        started += 1
        let mine = started
        let (found, read) = await Task.detached {
            downloadEvicted(folder)
            return (readLibrary(folder), readSavedQueries(folder))
        }.value
        guard mine == started else { return }
        papers = found
        saved = Set(found.compactMap(\.recid))
        tags = tagCounts(found).map { TagCount(tag: $0.tag, count: $0.count) }
        queries = read
    }

    /// Reads the folder again, without waiting for it
    func refresh() {
        Task { await reload() }
    }

    /// The paper's entry: of those with its recid, the first by folder name
    func paper(_ recid: Int) -> SavedPaper? {
        papers.filter { $0.recid == recid }.min { namePrecedes($0.name, $1.name) }
    }

    /// Saves the paper: creates its entry, or updates it. false if it could not
    @discardableResult
    func save(_ record: Record) -> Bool {
        guard let folder else {
            choosingFolder = true
            return false
        }
        defer { refresh() }
        do {
            try savePaper(folder, record, now: timestamp())
            return true
        } catch {
            self.error = message(error, "the paper")
            return false
        }
    }

    /// Updates a saved paper's entry from the record its page loaded
    func update(_ record: Record) {
        guard let folder, saved.contains(record.recid) else { return }
        if (try? savePaper(folder, record, now: timestamp())) == true { refresh() }
    }

    /// Deletes the paper's entry, its folder with all it holds: there is no trash for the user's
    /// folders. Ask first
    func remove(_ recid: Int) {
        change("the paper") { try removePaper($0, recid, delete: FileManager.default.removeItem) }
    }

    /// Keeps a PDF downloaded from arXiv in the paper's entry
    func keepPDF(_ recid: Int, _ data: Data) throws {
        guard let folder else { return }
        defer { refresh() }
        try savePDF(folder, recid, data)
    }

    /// Deletes the PDF Heplio downloaded. Ask first
    func deletePDF(_ recid: Int) {
        change("the PDF") { try removePDF($0, recid, delete: FileManager.default.removeItem) }
    }

    func attach(_ tag: String, to recid: Int) {
        change("the paper") { try addTag($0, recid, tag) }
    }

    func detach(_ tag: String, from recid: Int) {
        change("the paper") { try removeTag($0, recid, tag) }
    }

    // MARK: Saved queries

    /// Whether a query can be saved: there is a folder, and its queries.json is readable
    var canSaveQueries: Bool {
        folder != nil && queries != .unreadable
    }

    func isSaved(_ query: Query) -> Bool {
        queries.list.contains { $0.q == query.q && $0.sort == query.sort }
    }

    func saveQuery(_ query: Query) {
        change("the saved queries") { try addQuery($0, query) }
    }

    func deleteQuery(_ shown: Query, at index: Int) {
        changeQuery(shown, at: index) { try removeQuery($0, at: index) }
    }

    func reorderQuery(_ shown: Query, from: Int, to: Int) {
        changeQuery(shown, at: from) { try moveQuery($0, from: from, to: to) }
    }

    func rename(_ shown: Query, at index: Int, to name: String) {
        let name = name.trimmed
        guard !name.isEmpty else { return }
        changeQuery(shown, at: index) { try renameQuery($0, at: index, to: name) }
    }

    /// Changes the query at `index`, if it is still the one shown: another device may have
    /// changed the file
    private func changeQuery(_ shown: Query, at index: Int, _ action: (URL) throws -> Void) {
        guard let folder else { return }
        let list = readSavedQueries(folder).list
        guard list.indices.contains(index), list[index] == shown else {
            error = "The saved queries changed. Try again."
            return refresh()
        }
        change("the saved queries", action)
    }

    // MARK: Search history

    func addToHistory(_ text: String) {
        remember(&history, text)
        storeHistory()
    }

    func removeFromHistory(_ text: String) {
        forget(&history, text)
        storeHistory()
    }

    func clearHistory() {
        history = []
        storeHistory()
    }

    private func storeHistory() {
        defaults.set(history, forKey: "history")
    }
}

/// iCloud Drive leaves a file that is not on the device as `.<name>.icloud`, so an entry whose
/// `entry.json` was evicted is not an entry. Asks for those files, for a later reload to find
private func downloadEvicted(_ folder: URL) {
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !isHidden(name) {
        let dir = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: dir.appendingPathComponent(".\(entryFile).icloud").path) {
            try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(entryFile))
        }
    }
}

/// A short message for a failed read or write of `what`
func message(_ error: Error, _ what: String) -> String {
    if let error = error as? CoreError { return error.localizedDescription }
    if let error = error as? CocoaError, [.fileWriteNoPermission, .fileReadNoPermission].contains(error.code) {
        return "No permission to write \(what)."
    }
    return "Could not write \(what)."
}

// MARK: - Tabs

/// Library, every saved paper, and Search, of INSPIRE or of the library
struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var library = library
        TabView {
            Tab("Library", systemImage: "books.vertical") {
                Stack { LibraryPage() }
            }
            // A search tab only where the tab bar is at the top: at the bottom, it would turn the
            // tab bar into its field
            if sizeClass == .regular {
                Tab(role: .search) {
                    Stack { SearchPage() }
                }
            } else {
                Tab("Search", systemImage: "magnifyingglass") {
                    Stack { SearchPage() }
                }
            }
        }
        // A synced change shows when the user comes back
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refresh() }
        }
        .choosesFolder($library.choosingFolder)
        .showsErrors()
    }
}

extension View {
    /// The library's errors in an alert. On the root, and on sheets, over which the root's alert
    /// cannot be presented
    func showsErrors() -> some View {
        modifier(ShowsErrors())
    }

    /// The folder picker, which opens the folder chosen as the library
    func choosesFolder(_ isPresented: Binding<Bool>) -> some View {
        modifier(ChoosesFolder(isPresented: isPresented))
    }

    /// A button in the toolbar that shows Settings
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}

private struct ShowsErrors: ViewModifier {
    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content.alert("Error", isPresented: Binding { library.error != nil } set: { if !$0 { library.error = nil } }) {
            Button("OK") {}
        } message: {
            Text(library.error ?? "")
        }
    }
}

private struct ChoosesFolder: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): library.choose(url)
            case .failure(let error): library.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Navigation

/// The pages pushed over a tab's first
enum Route: Hashable {
    /// The papers of a query; `name` is the page's title
    case list(Query)
    case paper(Int)
    /// All the authors of a paper
    case authors([Author])
    /// The saved papers with a tag
    case tag(String)
}

/// A tab's navigation stack
struct Stack<Root: View>: View {
    @ViewBuilder let root: Root

    var body: some View {
        NavigationStack {
            root.navigationDestination(for: Route.self) { Destination(route: $0) }
        }
    }
}

/// The page of a route
struct Destination: View {
    let route: Route

    var body: some View {
        switch route {
        case .list(let query): ListPage(query: query)
        case .paper(let recid): PaperPage(recid: recid)
        case .authors(let authors): AuthorsPage(authors: authors)
        case .tag(let tag): TagPage(tag: tag)
        }
    }
}

// MARK: - Settings

private struct SettingsButton: ViewModifier {
    @Environment(Library.self) private var library
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showing = true }
                        .keyboardShortcut(",")
                }
            }
            // From the page, not the toolbar item, where it may not appear
            .sheet(isPresented: $showing) {
                SettingsView()
                    .environment(library)
            }
    }
}

/// The library folder, the search history, and About
struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var clearing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder") {
                        Text(verbatim: library.folder?.lastPathComponent ?? "None")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Choose Folder…") { choosing = true }
                    Button("Reload") { library.refresh() }
                        .keyboardShortcut("r")
                        .disabled(library.folder == nil)
                } header: {
                    Text("Library")
                } footer: {
                    Text("Saved papers and queries are files in this folder, which other refdir apps can open too. To use it on other devices, keep it in iCloud Drive or in a folder another app syncs.")
                }
                Section {
                    Button("Clear Search History", role: .destructive) { clearing = true }
                        .disabled(library.history.isEmpty)
                } footer: {
                    Text("Recent searches are kept on this device only.")
                }
                Section {
                    NavigationLink("About Heplio") { About() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .choosesFolder($choosing)
            .showsErrors()
            .confirmationDialog("Clear Search History", isPresented: $clearing) {
                Button("Clear Search History", role: .destructive) { library.clearHistory() }
            }
        }
    }
}

/// What the app is, and its version
private struct About: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("License", value: "MIT")
            } footer: {
                Text("An unofficial client for INSPIRE-HEP, the literature database of high-energy physics. Heplio is not affiliated with or endorsed by INSPIRE or CERN. Records, abstracts, and figures come from INSPIRE, and PDFs from arXiv, under their own terms.")
            }
            Section {
                Link("INSPIRE-HEP", destination: URL(string: "https://inspirehep.net")!)
                Link("The refdir Library Format", destination: URL(string: "https://github.com/xiupos/refdir")!)
                Link("Source Code", destination: URL(string: "https://github.com/xiupos/HeplioApp")!)
            }
        }
        .navigationTitle("Heplio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
