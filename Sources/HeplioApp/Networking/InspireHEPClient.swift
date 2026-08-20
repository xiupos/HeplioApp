import Foundation

enum InspireHEPError: Error {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case rateLimited
    case decoding(Error)
}

actor InspireHEPClient {
    static let shared = InspireHEPClient()

    /// INSPIRE's `sort` parameter, plus the ordering you get by not
    /// sending one at all.
    enum SortOrder: String, CaseIterable, SortOption {
        /// INSPIRE's own text ranking, which is what it returns when
        /// `sort` is absent. There is no spelling for this — see
        /// `queryValue`.
        case relevance
        case mostRecent = "mostrecent"
        case mostCited = "mostcited"

        /// What to put in `sort=`, or nil to leave the parameter off.
        ///
        /// Relevance has to be expressed as *absence*, not as a magic
        /// word: INSPIRE silently ignores values it doesn't recognize
        /// (verified — `sort=garbage123` returns HTTP 200 with
        /// relevance-ordered results), so guessing a name like
        /// `bestmatch` would look like it worked whether or not it did.
        /// Omitting the parameter is the only way to ask for this and
        /// know what you got.
        var queryValue: String? {
            self == .relevance ? nil : rawValue
        }

        var label: String {
            switch self {
            case .relevance: return "Relevance"
            case .mostRecent: return "Most Recent"
            case .mostCited: return "Most Cited"
            }
        }

        var systemImage: String {
            switch self {
            case .relevance: return "sparkle.magnifyingglass"
            case .mostRecent: return "clock"
            case .mostCited: return "quote.bubble"
            }
        }
    }

    private let baseURL = URL(string: "https://inspirehep.net/api")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    // INSPIRE enforces 15 requests/5s per IP, and blocked requests still
    // count toward the quota, so we throttle client-side instead of retrying.
    private let maxRequestsPerWindow = 15
    private let window: TimeInterval = 5
    private var requestTimestamps: [Date] = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchLiterature(
        query: String,
        sort: SortOrder = .mostRecent,
        page: Int = 1,
        size: Int = 25
    ) async throws -> [Paper] {
        let response: SearchResponse = try await fetch(
            literatureURL(query: query, sort: sort, page: page, size: size)
        )
        return response.hits.hits.map(\.paper)
    }

    func paperDetails(id: Int) async throws -> Paper {
        let url = baseURL.appendingPathComponent("literature/\(id)")
        let record: InspireRecord = try await fetch(url)
        return record.paper
    }

    /// Papers citing the given record, via INSPIRE's `refersto` query — the
    /// same search shape as `searchLiterature`, just with a different `q`.
    func citations(
        for id: Int,
        sort: SortOrder = .mostRecent,
        page: Int = 1,
        size: Int = 25
    ) async throws -> [Paper] {
        let response: SearchResponse = try await fetch(
            literatureURL(query: "refersto:recid:\(id)", sort: sort, page: page, size: size)
        )
        return response.hits.hits.map(\.paper)
    }

    /// Builds a `/literature` URL. Shared by both endpoints above so that
    /// the `+` fix below can't apply to one and not the other.
    ///
    /// `URLComponents` leaves a literal `+` in a query value alone, and
    /// the server reads `+` in a query string as a space — so INSPIRE saw
    /// `topcite 1000+` as `topcite 1000`, silently answering with papers
    /// cited exactly a thousand times instead of at least that. Anything
    /// with a `+` in it was quietly wrong; the citation-threshold queries
    /// are just where it finally showed.
    private func literatureURL(query: String, sort: SortOrder, page: Int, size: Int) -> URL {
        // Force-unwrapped deliberately: the base URL is a compile-time
        // constant and every component here is escaped, so a nil would be
        // a programming error rather than anything a caller could cause.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("literature"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            // Omitted entirely for `.relevance`, which is INSPIRE's
            // default ordering and has no name to send.
            sort.queryValue.map { URLQueryItem(name: "sort", value: $0) },
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ].compactMap { $0 }
        let escaped = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        components.percentEncodedQuery = escaped
        return components.url!
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        await throttle()
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InspireHEPError.invalidResponse(statusCode: -1)
        }
        if httpResponse.statusCode == 429 {
            throw InspireHEPError.rateLimited
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InspireHEPError.invalidResponse(statusCode: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw InspireHEPError.decoding(error)
        }
    }

    /// Blocks until issuing another request keeps us under 15 requests / 5s.
    private func throttle() async {
        let now = Date()
        requestTimestamps.removeAll { now.timeIntervalSince($0) >= window }

        if requestTimestamps.count >= maxRequestsPerWindow, let oldest = requestTimestamps.first {
            let waitTime = window - now.timeIntervalSince(oldest)
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            requestTimestamps.removeAll { Date().timeIntervalSince($0) >= window }
        }

        requestTimestamps.append(Date())
    }

    private struct SearchResponse: Decodable {
        let hits: Hits

        struct Hits: Decodable {
            let total: Int
            let hits: [InspireRecord]

            enum CodingKeys: String, CodingKey {
                case total
                case hits
            }
        }

        enum CodingKeys: String, CodingKey {
            case hits
        }
    }
}

/// Which orderings a screen offers. Declared on the array rather than on
/// `SortOrder` itself so `sortToolbarItem(_:options:)` — whose parameter
/// is `[SortOrder]` — can take them as `.searchOptions` / `.browseOptions`.
/// Leading-dot syntax resolves against the parameter's own type, and the
/// parameter is the array, not the element.
extension Array where Element == InspireHEPClient.SortOrder {
    /// What a keyword search offers. Relevance leads because it's the
    /// only one that answers "which of these 9,000 papers did I mean":
    /// sorted by date, a search for "dark matter direct detection" opens
    /// on yesterday's uncited preprints.
    static var searchOptions: Self { [.relevance, .mostRecent, .mostCited] }

    /// What a browse screen offers. Relevance is left out on purpose —
    /// `authors.recid:1234` or `primarch hep-th` match every hit equally,
    /// so there's nothing for a text ranking to rank.
    static var browseOptions: Self { [.mostRecent, .mostCited] }
}
