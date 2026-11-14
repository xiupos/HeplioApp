// The saved papers: covers, cards, the Library tab, searching the library, and tags' pages; and
// the views pages share

import CryptoKit
import PDFKit
import SwiftUI

// MARK: - Covers

/// A paper's cover: its PDF's first page, else an icon. A page's shape, whatever the PDF's
struct Cover: View {
    let pdf: URL?
    var systemImage = "doc.text"
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(8.5 / 11, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: systemImage)
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            // A hairline, so that a white page shows on a white background
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
            }
            .task(id: pdf) {
                image = nil
                if let pdf { image = await Covers.shared.image(of: pdf) }
            }
    }
}

/// Covers are rendered on the device with PDFKit, one at a time, off the main thread, and kept as
/// PNG in the app's caches, named by the SHA-1 of the PDF's path. One older than its PDF is
/// rendered again. No PDF is downloaded for a cover
actor Covers {
    static let shared = Covers()
    /// In points: a little more than the cards' width
    private let width: CGFloat = 200
    /// Changed when covers are rendered otherwise, so that the old ones are not used
    private let version = 2
    private let memory = NSCache<NSString, UIImage>()

    func image(of pdf: URL) -> UIImage? {
        guard let modified = modified(pdf) else { return nil }
        let key = "\(pdf.path)\n\(modified.timeIntervalSince1970)" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        let file = URL.cachesDirectory.appendingPathComponent("covers/\(version)/\(sha1(pdf.path)).png")
        if let made = self.modified(file), made >= modified, let image = UIImage(contentsOfFile: file.path) {
            memory.setObject(image, forKey: key)
            return image
        }
        guard let image = render(pdf) else { return nil }
        if let png = image.pngData() {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
        memory.setObject(image, forKey: key)
        return image
    }

    /// The first page as a viewer shows it: its crop box, turned by its rotation. PDFKit does
    /// both; a landscape page is often a portrait one turned 90°
    private func render(_ pdf: URL) -> UIImage? {
        guard let page = PDFDocument(url: pdf)?.page(at: 0) else { return nil }
        let box = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        let (w, h) = turned ? (box.height, box.width) : (box.width, box.height)
        guard w > 0, h > 0 else { return nil }
        return page.thumbnail(of: CGSize(width: width, height: (width * h / w).rounded()), for: .cropBox)
    }

    private func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// The SHA-1 of a text, in hex
func sha1(_ text: String) -> String {
    Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Cards

/// A saved paper, as Books shows a book: its cover, its title, and its first author and date. An
/// unreadable entry shows its folder's name, and opens nothing
struct PaperCard: View {
    let paper: SavedPaper

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Cover(pdf: paper.pdf, systemImage: paper.recid == nil ? "exclamationmark.triangle" : "doc.text")
                .padding(.bottom, 4)
            Text(verbatim: paper.title ?? paper.name)
                .font(.subheadline)
                .lineLimit(2)
            Text(verbatim: paper.recid == nil ? "Can't be read"
                 : [paper.byline, paper.date ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Saved papers in a grid of cards, each opening its paper
struct CardGrid: View {
    let papers: [SavedPaper]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)], spacing: 24) {
            ForEach(papers) { paper in
                if let recid = paper.recid {
                    NavigationLink(value: Route.paper(recid)) {
                        PaperCard(paper: paper)
                    }
                    .buttonStyle(.plain)
                } else {
                    PaperCard(paper: paper)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Library

/// The Library tab: every saved paper, newest first. It is never searched, so that it keeps its
/// place; the Search tab finds among them
struct LibraryPage: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if library.folder == nil {
                NoFolder()
            } else if library.papers.isEmpty {
                ContentUnavailableView("No Saved Papers", systemImage: "books.vertical",
                                       description: Text("Save a paper from its page."))
            } else {
                ScrollView {
                    CardGrid(papers: library.papers)
                        .padding(.vertical)
                }
                .refreshable { await library.reload() }
            }
        }
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .settingsButton()
    }
}

/// Asks for a library folder, where there is none
private struct NoFolder: View {
    @Environment(Library.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label("No Library Folder", systemImage: "folder")
        } description: {
            Text("Choose a folder to keep saved papers and queries in. Keep it in iCloud Drive, or in a folder another app syncs, to use it on other devices.")
        } actions: {
            Button("Choose Folder…") { library.choosingFolder = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Searching the library

/// What the Search tab shows for the library: the saved papers that `text` finds, with the tags
/// that match above them; while it is empty, the library's tags by namespace. Nothing here uses
/// the network
struct LibraryResults: View {
    let text: String
    @Environment(Library.self) private var library

    var body: some View {
        if library.folder == nil {
            NoFolder()
        } else if text.isEmpty {
            tags
        } else {
            found
        }
    }

    /// The library's tags under their namespace, capitalized, and those without one last
    private var tags: some View {
        List {
            ForEach(namespaces(library.tags)) { group in
                Section(heading(group.name)) {
                    ForEach(group.tags) { tag in
                        NavigationLink(value: Route.tag(tag.tag)) {
                            LabeledContent {
                                Text(tag.count, format: .number)
                            } label: {
                                Text(verbatim: splitTag(tag.tag).value)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if library.tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag",
                                       description: Text("Tags you add to saved papers appear here."))
            }
        }
        .refreshable { await library.reload() }
    }

    private var found: some View {
        let papers = library.papers.filter { $0.matches(text) }
        let tags = library.tags.filter { tagMatches($0.tag, text) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !tags.isEmpty {
                    TagLinks(tags: tags, fullNames: true)
                }
                CardGrid(papers: papers)
            }
            .padding(.vertical)
        }
        .overlay {
            if papers.isEmpty && tags.isEmpty {
                ContentUnavailableView.search(text: text)
            }
        }
    }
}

/// The tags of a namespace; "" for those without one
private struct TagGroup: Identifiable {
    let name: String
    var tags: [TagCount]
    var id: String { name }
}

/// The library's tags by namespace, in its order, with those without one last
private func namespaces(_ tags: [TagCount]) -> [TagGroup] {
    var groups: [TagGroup] = []
    for tag in tags {
        let name = splitTag(tag.tag).namespace ?? ""
        if let i = groups.firstIndex(where: { $0.name == name }) {
            groups[i].tags.append(tag)
        } else {
            groups.append(TagGroup(name: name, tags: [tag]))
        }
    }
    return groups.filter { !$0.name.isEmpty } + groups.filter { $0.name.isEmpty }
}

/// A namespace as a heading: its first letter in upper case. "Other Tags" for none
private func heading(_ namespace: String) -> String {
    namespace.isEmpty ? "Other Tags" : namespace.prefix(1).uppercased() + namespace.dropFirst()
}

/// A part of a page under its heading, as the App Store has them. The content has its own margins,
/// so that a row of things can scroll to the edges
struct Shelf<Content: View>: View {
    let heading: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: heading)
                .font(.title3.bold())
                .padding(.horizontal)
            content
        }
    }
}

/// Its subviews with a line between each two: rows down, or tiles across
struct Separated<Content: View>: View {
    var axis = Axis.vertical
    @ViewBuilder let content: Content

    var body: some View {
        let stack = axis == .vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                      : AnyLayout(HStackLayout(spacing: 0))
        stack {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { i in
                    if i > 0 {
                        Divider()
                            .padding(.leading, axis == .vertical ? 16 : 0)
                    }
                    subviews[i]
                }
            }
        }
    }
}

/// Tags side by side, each opening its page, with the number of its papers, and `trailing` after
/// them
struct TagLinks<Trailing: View>: View {
    let tags: [TagCount]
    /// With their namespace, where tags of several are shown together
    let fullNames: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    NavigationLink(value: Route.tag(tag.tag)) {
                        HStack(spacing: 4) {
                            Text(verbatim: fullNames ? tag.tag : splitTag(tag.tag).value)
                            Text(tag.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                trailing
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}

extension TagLinks where Trailing == EmptyView {
    init(tags: [TagCount], fullNames: Bool) {
        self.init(tags: tags, fullNames: fullNames) { EmptyView() }
    }
}

/// The saved papers with a tag, as written, in the Library's order
struct TagPage: View {
    let tag: String
    @Environment(Library.self) private var library

    var body: some View {
        let papers = library.papers.filter { $0.has(tag: tag) }
        ScrollView {
            CardGrid(papers: papers)
                .padding(.vertical)
        }
        .overlay {
            if papers.isEmpty {
                ContentUnavailableView("No Papers", systemImage: "tag",
                                       description: Text("No saved paper has this tag."))
            }
        }
        .refreshable { await library.reload() }
        .navigationTitle(tag)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A tag in a row: its value, with its namespace after it
struct TagLabel: View {
    let tag: String

    var body: some View {
        let parts = splitTag(tag)
        LabeledContent {
            if let namespace = parts.namespace { Text(verbatim: namespace) }
        } label: {
            Text(verbatim: parts.value)
        }
    }
}
