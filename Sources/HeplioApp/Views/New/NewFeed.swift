import Foundation

/// What the New tab's picker is set to: everything the app covers, or one
/// arXiv category.
///
/// `Foundation`-only on purpose — the whole tab reduces to a query string
/// and a way of cutting the answer into days, and both of those can be
/// checked against the live API from a scratch executable.
enum NewFeedSelection: Hashable, Identifiable {
    case all
    case category(ArxivCategory)

    /// Hand-written rather than synthesized: `CaseIterable` can't be
    /// derived for an enum with associated values.
    static let allCases: [NewFeedSelection] = [.all] + ArxivCategory.allCases.map(NewFeedSelection.category)

    /// How far back the feed reaches. New is about time, so it's a window
    /// rather than an endless scroll into the archive: two weeks is a few
    /// hundred papers per category, and long enough that a reader who was
    /// away for a week hasn't missed anything.
    ///
    /// It also decides how often the tab talks to INSPIRE. The window's
    /// start date is part of the query, so it moves at midnight and the
    /// day's first look is a real fetch — see `Date.daysAgo(_:)`.
    static let windowDays = 14

    /// Stable across launches, so the picker's position survives in
    /// `@AppStorage`. `init(id:)` is total rather than failable: an id
    /// written by a build that carried a category this one doesn't falls
    /// back to "All" instead of leaving the tab empty.
    var id: String {
        switch self {
        case .all: return ""
        case .category(let category): return category.rawValue
        }
    }

    init(id: String) {
        self = ArxivCategory(rawValue: id).map(NewFeedSelection.category) ?? .all
    }

    /// The chip's label. Categories go by their arXiv identifier, not
    /// their spelled-out name: this audience says "hep-ph" out loud, and
    /// twelve names the length of "High Energy Astrophysics" would be a
    /// menu rather than a row of chips.
    var label: String {
        switch self {
        case .all: return "All"
        case .category(let category): return category.rawValue
        }
    }

    /// INSPIRE's `feedQuery` (cross-lists included — a hep-ph paper
    /// cross-listed to hep-th is something a hep-th reader wants), bounded
    /// to the window.
    ///
    /// "All" is the union of the twelve categories rather than an
    /// unfiltered query, and it has to be. Asked for everything recent,
    /// INSPIRE leads with journal records whose `earliest_date` is a
    /// *future* month — "2026-12", month precision, no arXiv entry —
    /// which would open the tab on papers that aren't out yet and can't be
    /// filed under a day. Requiring an arXiv category is what makes every
    /// entry a dated preprint.
    var query: String {
        let start = Date.daysAgo(Self.windowDays).inspireDay
        switch self {
        case .all:
            // Parenthesised: `de > X and A or B` binds the wrong way and
            // would quietly return all of B, window or not.
            let union = ArxivCategory.allCases.map(\.feedQuery).joined(separator: " or ")
            return "de > \(start) and (\(union))"
        case .category(let category):
            return "de > \(start) and \(category.feedQuery)"
        }
    }
}

/// One day of the feed, and the section it becomes on screen.
struct PaperDay: Identifiable {
    /// INSPIRE's own `earliest_date` string, which doubles as the section
    /// id — the feed is date-ordered, so each value appears in exactly one
    /// run.
    let id: String
    let papers: [Paper]

    /// "Today" / "Yesterday" / "Wednesday, August 19", the way a newspaper
    /// dates a page.
    ///
    /// The component count is checked before parsing rather than trusting
    /// `DateFormatter` to reject a partial date: INSPIRE publishes
    /// year- and month-precision dates too, and `yyyy-MM-dd` will happily
    /// read "2026-12" as the first of December. A date it can't place to
    /// the day is shown as INSPIRE wrote it.
    var title: String {
        guard id.split(separator: "-").count == 3,
              let date = DateFormatter.inspireDay.date(from: id) else {
            return id.isEmpty ? "Undated" : id
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

extension Array where Element == Paper {
    /// Cuts a date-ordered feed into day sections, in the order it arrived.
    ///
    /// Contiguity, not sorting: INSPIRE's `mostrecent` already hands back
    /// non-increasing dates (verified over 50 hits), so grouping runs of
    /// equal dates preserves both the ordering and the fact that a page
    /// loaded later simply extends the day it fell in.
    func groupedByDay() -> [PaperDay] {
        var days: [PaperDay] = []
        var currentDate: String?
        var current: [Paper] = []

        for paper in self {
            let date = paper.earliestDate ?? ""
            if date != currentDate {
                if let currentDate { days.append(PaperDay(id: currentDate, papers: current)) }
                currentDate = date
                current = []
            }
            current.append(paper)
        }
        if let currentDate { days.append(PaperDay(id: currentDate, papers: current)) }
        return days
    }
}
