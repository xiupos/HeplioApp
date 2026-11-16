// INSPIRE-HEP's search, papers, and BibTeX, and PDFs from arXiv. What it asks and how it reads the
// answers is Core's; this is only the network

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A short sentence, shown as it is
struct Failure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

enum Fetch {
    /// The program and where to find it, as INSPIRE asks of its clients
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Heplio/\(version) (iOS; https://github.com/xiupos/HeplioApp)"
    }()

    /// Without a cache: INSPIRE's, 30 seconds; arXiv's PDFs, 5 minutes. Either fails after 30
    /// seconds without data, so that a stalled network says so
    private static let short = session(30)
    private static let long = session(300)

    private static func session(_ seconds: Double) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = seconds
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    /// A page of a query's papers, and how many it finds in all
    static func search(_ query: Query, page: Int) async throws -> (total: Int, records: [Record]) {
        guard let found = parseSearch(try await get(listURL(query, page: page))) else {
            throw Failure("INSPIRE gave an answer Heplio cannot read.")
        }
        return found
    }

    /// A paper, with all its details
    static func paper(_ recid: Int) async throws -> Record {
        guard let paper = parseSearch(try await get(paperURL(recid)))?.records.first else {
            throw Failure("INSPIRE does not have it.")
        }
        return paper
    }

    /// A paper's BibTeX, as INSPIRE writes it
    static func bibtex(_ recid: Int) async throws -> String {
        String(decoding: try await get(bibtexURL(recid)), as: UTF8.self).trimmed + "\n"
    }

    /// A page of a query's papers as BibTeX, as INSPIRE writes it
    static func listBibtex(_ query: Query, page: Int) async throws -> String {
        String(decoding: try await get(listBibtexURL(query, page: page)), as: UTF8.self).trimmed
    }

    /// A paper's PDF from arXiv: what does not start as a PDF is refused
    static func pdf(_ arxiv: String) async throws -> Data {
        let data = try await get(pdfURL(arxiv), session: long)
        guard data.starts(with: Data("%PDF-".utf8)) else { throw Failure("arXiv gave no PDF.") }
        return data
    }

    /// Failures of a connection kept from before, which the network dropped meanwhile: the first
    /// request on it fails, and the next, on a new one, does not
    private static let dropped: Set<URLError.Code> = [.networkConnectionLost, .cannotConnectToHost,
                                                      .secureConnectionFailed]

    /// A response. Errors are short sentences naming the host, INSPIRE or arXiv; the details go to
    /// the console. A request whose task was cancelled, as a view's is when it goes, is a
    /// `CancellationError`, which is no failure to show
    private static func get(_ url: URL, session: URLSession = short) async throws -> Data {
        let host = url.host?.contains("arxiv") == true ? "arXiv" : "INSPIRE"
        var answer: (Data, URLResponse)?
        for attempt in 1...2 where answer == nil {
            do {
                answer = try await session.data(from: url)
            } catch {
                let code = (error as? URLError)?.code
                if Task.isCancelled || code == .cancelled { throw CancellationError() }
                print("\(url): \(error)")
                guard attempt == 1, let code, dropped.contains(code) else {
                    throw Failure("\(host) cannot be reached.")
                }
            }
        }
        guard let (data, response) = answer else { throw Failure("\(host) cannot be reached.") }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 404: throw Failure("\(host) does not have it.")
        case 429: throw Failure("\(host) is limiting requests: wait a few seconds.")
        case let code: throw Failure("\(host) answered with error \(code).")
        }
    }
}
