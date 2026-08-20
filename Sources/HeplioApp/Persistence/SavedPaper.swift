import Foundation
import SwiftData

/// A bookmarked paper. There's one kind of saving — no folders, no
/// collections — so this is a flat list, which the Library tab sorts and
/// filters with `LibrarySort` over the columns below.
@Model
final class SavedPaper: PaperRecord {
    var paperID: Int = 0
    var title: String = ""
    var firstAuthor: String = ""
    var year: Int = 0
    /// Frozen at the moment of saving, like the rest of the snapshot — a
    /// paper saved at 10 citations still reads 10 a year later. Fine for
    /// a row, and the reason `LibrarySort.citations` is labelled "as
    /// saved" rather than pretending to be live.
    var citationCount: Int = 0
    var savedAt: Date = Date.now
    var snapshot: Data = Data()

    init(paper: Paper, savedAt: Date = .now) {
        self.paperID = paper.id
        self.savedAt = savedAt
        self.snapshot = PaperSnapshot.encode(paper)
        applyMetadata(from: paper)
    }
}
