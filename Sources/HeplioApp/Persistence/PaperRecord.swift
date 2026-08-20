import Foundation
import SwiftData

/// Shared shape of the stored models that stand for a paper — `SavedPaper`
/// and `ViewedPaper`. Each keeps a JSON snapshot of the `Paper` so the
/// Library and History lists render exactly like search results, offline
/// and without spending requests.
///
/// The snapshot is opaque to SwiftData, so anything the Library needs to
/// sort or filter on is also stored as a real column: `paperID` for
/// de-duplication, and `title` / `firstAuthor` / `year` / `citationCount`
/// for the sort menu and the search field. Duplicated on purpose —
/// decoding every snapshot on each keystroke is the alternative, and it
/// gets slower with every paper saved.
protocol PaperRecord: PersistentModel {
    var paperID: Int { get }
    var title: String { get set }
    var firstAuthor: String { get set }
    var year: Int { get set }
    var citationCount: Int { get set }
    var snapshot: Data { get set }
}

extension PaperRecord {
    var paper: Paper? { PaperSnapshot.decode(snapshot) }

    /// Copies the queryable columns off a paper. One place, so the two
    /// models and the backfill can't disagree about what goes where.
    func applyMetadata(from paper: Paper) {
        title = paper.title
        firstAuthor = paper.authors.first?.fullName ?? paper.collaborations.first ?? ""
        year = paper.year ?? 0
        citationCount = paper.citationCount
    }
}

/// Encoding for the stored snapshots, in one place so both models agree.
enum PaperSnapshot {
    static func encode(_ paper: Paper) -> Data {
        (try? JSONEncoder().encode(paper.summary)) ?? Data()
    }

    static func decode(_ data: Data) -> Paper? {
        try? JSONDecoder().decode(Paper.self, from: data)
    }
}
