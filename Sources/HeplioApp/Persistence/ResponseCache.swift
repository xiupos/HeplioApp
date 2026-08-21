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
    /// Bytes stored since the last budget check. Scanning the directory
    /// costs a `stat` per file, so it isn't worth doing on every write —
    /// but it has to happen more often than once a launch, or a long
    /// session of scrolling Home can run well past the limit before
    /// anything notices.
    private var bytesSinceBudgetCheck: Int64 = 0
    private static let budgetCheckInterval: Int64 = 5 * 1024 * 1024

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

        bytesSinceBudgetCheck += Int64(data.count)
        if bytesSinceBudgetCheck >= Self.budgetCheckInterval {
            bytesSinceBudgetCheck = 0
            enforceBudget()
        }
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

    /// Deletes oldest-first until the directory fits the reader's chosen
    /// budget. Runs at launch beside `prune()` and periodically as entries
    /// are written.
    ///
    /// **Oldest-first, but never a protected key while an unprotected one
    /// is still there.** Nothing in this directory is irreplaceable — the
    /// library and history keep their own snapshots, so a paper the reader
    /// saved survives having its cache entry dropped. But not everything
    /// costs the same to lose: the `detail|<id>` record behind a saved
    /// paper is the one entry that makes that paper readable with no
    /// network, and re-fetching it costs a request from a budget INSPIRE
    /// caps at 15 per 5 seconds. So those go last, and in practice never
    /// — a library of a few hundred papers is a few MB against a budget
    /// measured in hundreds.
    ///
    /// The caller supplies the protected keys rather than this actor
    /// looking them up: a cache has no business reaching into SwiftData.
    func enforceBudget(protecting protectedKeys: Set<String> = []) {
        let budget = Self.budget
        guard budget > 0 else { return }

        let protectedFiles = Set(protectedKeys.map(fileName(for:)))
        var entries = files().compactMap { url -> (url: URL, size: Int64, stored: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let stored = values.contentModificationDate else { return nil }
            return (url, Int64(size), stored)
        }

        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > budget else { return }

        entries.sort { lhs, rhs in
            let lhsProtected = protectedFiles.contains(lhs.url.lastPathComponent)
            let rhsProtected = protectedFiles.contains(rhs.url.lastPathComponent)
            if lhsProtected != rhsProtected { return !lhsProtected }
            return lhs.stored < rhs.stored
        }

        var evicted: Set<String> = []
        for entry in entries {
            guard total > budget else { break }
            try? FileManager.default.removeItem(at: entry.url)
            evicted.insert(entry.url.lastPathComponent)
            total -= entry.size
        }
        // Keep the memory front consistent with what's actually on disk,
        // so "cached" means one thing rather than two.
        memory = memory.filter { !evicted.contains(fileName(for: $0.key)) }
    }

    /// How much disk the reader has allowed this cache, or 0 for no
    /// limit. Read from `UserDefaults` on each use rather than captured,
    /// so changing it in Settings takes effect without a relaunch.
    static var budget: Int64 {
        let stored = UserDefaults.standard.object(forKey: budgetKey) as? Int
        return Int64(stored ?? defaultBudget)
    }

    static let budgetKey = "responseCacheBudgetBytes"
    static let defaultBudget = 500 * 1024 * 1024

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

    /// Named by a process-stable digest — see `String.fnv1aHash` for why
    /// `hashValue` can't be used to name a file that outlives a launch.
    private func fileURL(for key: String) -> URL {
        directory.appending(path: fileName(for: key))
    }

    private func fileName(for key: String) -> String {
        "\(String(key.fnv1aHash, radix: 16)).json"
    }

    private struct Entry: Codable {
        let storedAt: Date
        let papers: [Paper]

        var isFresh: Bool { Date.now.timeIntervalSince(storedAt) < ResponseCache.lifetime }
    }
}
