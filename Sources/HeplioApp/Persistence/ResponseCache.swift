import Foundation

/// Disk-backed (with an in-memory front) cache of API results, keyed by
/// request. Reopening a paper, backing out of a search, or scrolling a
/// carousel's "See All" list re-asks for things already fetched, and
/// INSPIRE only allows 15 requests per 5 seconds — so answering from here
/// is both faster and what keeps the app inside that budget.
actor ResponseCache {
    static let shared = ResponseCache()

    /// How long an entry stays usable. Literature records barely change
    /// (citation counts drift, little else), so a day keeps a whole
    /// session of browsing instant without going stale in any way a reader
    /// would notice.
    static let lifetime: TimeInterval = 60 * 60 * 24

    private let directory: URL
    private var memory: [String: Entry] = [:]

    init(directory: URL = URL.cachesDirectory.appending(path: "PaperResponses")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func papers(forKey key: String) -> [Paper]? {
        if let entry = memory[key] {
            return entry.isFresh ? entry.papers : nil
        }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.isFresh else { return nil }
        memory[key] = entry
        return entry.papers
    }

    func store(_ papers: [Paper], forKey key: String) {
        let entry = Entry(storedAt: .now, papers: papers)
        memory[key] = entry
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Forgets one request, so the next ask for it goes to the network.
    /// What backs pull-to-refresh.
    func remove(forKey key: String) {
        memory[key] = nil
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Everything the Settings screen's "Clear Cache" throws away.
    func clear() {
        memory.removeAll()
        for url in files() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Drops aged-out entries. Nothing else would ever notice them (reads
    /// already check freshness), so this only exists to stop the directory
    /// growing forever — cheap enough to run once at launch.
    func prune() {
        memory = memory.filter { $0.value.isFresh }
        for url in files() {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date.now.timeIntervalSince(modified) > Self.lifetime else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func diskSize() -> Int64 {
        files().reduce(into: 0) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
    }

    private func fileURL(for key: String) -> URL {
        directory.appending(path: "\(Self.digest(key)).json")
    }

    /// FNV-1a. `hashValue` is seeded per process, so it can't name a file
    /// that has to be found again after relaunch.
    private static func digest(_ key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private struct Entry: Codable {
        let storedAt: Date
        let papers: [Paper]

        var isFresh: Bool { Date.now.timeIntervalSince(storedAt) < ResponseCache.lifetime }
    }
}
