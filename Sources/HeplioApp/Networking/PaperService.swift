import Foundation

/// The one place views ask for papers. Wraps `InspireHEPClient` with the
/// response cache and in-flight de-duplication, so the same request made
/// twice — a detail screen and its References carousel both wanting the
/// record, a "See All" list re-asking for the page its carousel just
/// showed — costs a single trip to INSPIRE.
actor PaperService {
    static let shared = PaperService()

    /// One page everywhere: carousels show a page, lists load a page at a
    /// time, and the two then hit the same cache entries.
    static let pageSize = 10

    private let client: InspireHEPClient
    private let cache: ResponseCache
    private var inFlight: [String: Task<[Paper], Error>] = [:]

    init(client: InspireHEPClient = .shared, cache: ResponseCache = .shared) {
        self.client = client
        self.cache = cache
    }

    func search(
        query: String,
        sort: InspireHEPClient.SortOrder = .mostRecent,
        page: Int = 1,
        size: Int = PaperService.pageSize,
        refresh: Bool = false
    ) async throws -> [Paper] {
        try await papers(forKey: "search|\(sort.rawValue)|\(page)|\(size)|\(query)", refresh: refresh) { [client] in
            try await client.searchLiterature(query: query, sort: sort, page: page, size: size)
        }
    }

    func details(id: Int, refresh: Bool = false) async throws -> Paper {
        let results = try await papers(forKey: "detail|\(id)", refresh: refresh) { [client] in
            [try await client.paperDetails(id: id)]
        }
        guard let paper = results.first else { throw InspireHEPError.invalidResponse(statusCode: -1) }
        return paper
    }

    func citations(
        of id: Int,
        page: Int = 1,
        size: Int = PaperService.pageSize,
        refresh: Bool = false
    ) async throws -> [Paper] {
        try await papers(forKey: "citations|\(id)|\(page)|\(size)", refresh: refresh) { [client] in
            try await client.citations(for: id, page: page, size: size)
        }
    }

    /// One page of a paper's bibliography, with every entry INSPIRE has a
    /// record for swapped for that full record: the embedded citation text
    /// has no abstract and is often mangled (a bare "[CMS]" where the
    /// title should be). Unmatched entries pass through as the
    /// external-link-only papers the record already builds for them.
    ///
    /// `refresh` re-fetches the source record only. The referenced records
    /// themselves stay cached: they're separate papers that didn't change
    /// because this one was pulled down, and re-fetching all ten would
    /// spend most of a rate-limit window on nothing.
    func references(
        of id: Int,
        page: Int = 1,
        size: Int = PaperService.pageSize,
        refresh: Bool = false
    ) async throws -> [Paper] {
        let entries = try await details(id: id, refresh: refresh).references
        let start = (page - 1) * size
        guard start < entries.count else { return [] }
        return await resolve(Array(entries[start..<min(start + size, entries.count)]))
    }

    /// Fetches concurrently but reassembles in the original order, so
    /// reference numbering stays put.
    private func resolve(_ entries: [Paper]) async -> [Paper] {
        await withTaskGroup(of: (Int, Paper).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    guard entry.hasInspireRecord,
                          let full = try? await self.details(id: entry.id) else { return (index, entry) }
                    return (index, full)
                }
            }
            var resolved = entries
            for await (index, paper) in group { resolved[index] = paper }
            return resolved
        }
    }

    private func papers(
        forKey key: String,
        refresh: Bool = false,
        fetch: @escaping @Sendable () async throws -> [Paper]
    ) async throws -> [Paper] {
        // Registering the task before any `await` is what makes this
        // de-duplication airtight: no other caller can slip in between the
        // lookup and the insert. A refresh still joins an identical
        // request already in flight — that one is as fresh as it gets.
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task { [cache] in
            // A refresh skips the *read* rather than deleting the entry.
            // Deleting up front — which this used to do — threw the copy
            // away before knowing whether a replacement was coming, so a
            // pull-to-refresh with no signal left the reader worse off
            // than not having pulled: the entry that made the paper
            // readable offline was gone, and the fetch that was meant to
            // replace it had failed. A successful `store` overwrites it
            // anyway, so nothing is gained by clearing it first.
            if !refresh, let cached = await cache.papers(forKey: key) {
                return cached
            }
            do {
                let fresh = try await fetch()
                await cache.store(fresh, forKey: key)
                return fresh
            } catch let error as URLError where error.isOffline {
                // Nothing fresh cached and the network is unreachable, so
                // an aged-out entry beats a hard failure — see
                // `ResponseCache.stalePapers`. A refresh is excluded on
                // purpose: "show me this again, now" that can't reach the
                // network should say so rather than re-serve what's
                // already on screen. The entry itself survives either way.
                if !refresh, let stale = await cache.stalePapers(forKey: key) { return stale }
                throw error
            }
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}

private extension URLError {
    /// Codes that mean "never reached the server" rather than "the server
    /// answered badly" — the distinction that decides whether an aged-out
    /// cache entry is a reasonable fallback. A timeout is included: it's
    /// as often a dead connection as a slow one, and the alternative is a
    /// hard failure over a paper the reader has already read once.
    var isOffline: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .dataNotAllowed, .internationalRoamingOff, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
