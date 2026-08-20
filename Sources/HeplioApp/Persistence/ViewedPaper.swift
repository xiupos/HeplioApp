import Foundation
import SwiftData

/// A paper the reader opened — the History list behind the Library tab's
/// clock button, and (for the ones reached from search) the "Recently
/// Opened" section of the Search tab, the way Music lists what you tapped
/// through to from a search.
@Model
final class ViewedPaper: PaperRecord {
    var paperID: Int = 0
    var title: String = ""
    var firstAuthor: String = ""
    var year: Int = 0
    var citationCount: Int = 0
    var viewedAt: Date = Date.now
    /// Whether this visit started from the Search tab. Re-opening the same
    /// paper from somewhere else clears it, which is what keeps "Recently
    /// Opened" meaning "found by searching" rather than "ever searched".
    var fromSearch: Bool = false
    var snapshot: Data = Data()

    /// How many visits are kept. Old enough entries stop being "recent" to
    /// anyone, and this is a list nobody curates.
    static let limit = 100

    init(paper: Paper, fromSearch: Bool, viewedAt: Date = .now) {
        self.paperID = paper.id
        self.viewedAt = viewedAt
        self.fromSearch = fromSearch
        self.snapshot = PaperSnapshot.encode(paper)
        applyMetadata(from: paper)
    }
}
