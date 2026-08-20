import Foundation

/// Copies remote files into the temporary directory, because Quick Look
/// previews files on disk rather than URLs it fetches itself. Both things
/// the detail screen can preview — the arXiv PDF and the record's figures
/// — come through here.
///
/// Filenames are caller-supplied and have to carry an extension: Quick
/// Look works out the type from the path, and INSPIRE serves figures from
/// extension-less URLs. Anything already fetched this session is reused,
/// so reopening is instant.
enum TemporaryDownload {
    static func url(named filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    static func file(from source: URL, named filename: String) async throws -> URL {
        let destination = url(named: filename)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let (data, response) = try await URLSession.shared.data(from: source)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Concurrent, but reassembled in the caller's order — Quick Look
    /// swipes through the array as given, so it has to match what's on
    /// screen. Files that fail are dropped rather than failing the batch.
    static func files(_ items: [(source: URL, filename: String)]) async -> [URL] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, try? await file(from: item.source, named: item.filename)) }
            }
            var results = [URL?](repeating: nil, count: items.count)
            for await (index, url) in group { results[index] = url }
            return results.compactMap { $0 }
        }
    }
}

extension Paper.Figure {
    /// Figures are always PNG in practice, but their URLs don't say so.
    var previewFilename: String? {
        imageURL.map { "figure-\($0.lastPathComponent).png" }
    }

    var previewFileURL: URL? {
        previewFilename.map(TemporaryDownload.url(named:))
    }

    /// Paired up for `TemporaryDownload.files(_:)`.
    var downloadItem: (source: URL, filename: String)? {
        guard let imageURL, let previewFilename else { return nil }
        return (imageURL, previewFilename)
    }
}
