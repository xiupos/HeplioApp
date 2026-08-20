import Foundation
import SwiftData

/// A query the reader submitted, listed under "Recently Searched" when the
/// Search tab is idle. Tapping one runs it again.
@Model
final class RecentSearch {
    var text: String = ""
    var searchedAt: Date = Date.now

    static let limit = 20

    init(text: String, searchedAt: Date = .now) {
        self.text = text
        self.searchedAt = searchedAt
    }
}
