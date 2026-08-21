import Foundation

extension DateFormatter {
    /// INSPIRE's `yyyy-MM-dd`, and the `yyyy-MM` it falls back to for
    /// records it only knows the month of.
    ///
    /// Held as statics rather than built where they're needed, because
    /// two of the three callers are inside a view body — `formattedDate`
    /// runs once per row per render, and a `DateFormatter` is expensive to
    /// construct. They're never mutated after setup, which is the
    /// condition under which sharing one is safe.
    ///
    /// POSIX locale because these parse and emit a wire format, not
    /// anything anyone reads: under a Japanese or Buddhist calendar the
    /// same code would quietly produce a date INSPIRE answers to with
    /// nothing.
    static let inspireDay = fixedFormat("yyyy-MM-dd")
    static let inspireMonth = fixedFormat("yyyy-MM")

    private static func fixedFormat(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

extension Date {
    /// This date as INSPIRE's `yyyy-MM-dd`, the only form its `de`
    /// operator takes.
    var inspireDay: String { DateFormatter.inspireDay.string(from: self) }

    /// The start of a rolling window `days` back from now.
    ///
    /// Deliberately computed per call rather than cached at launch. It
    /// moves once a day, and that does two things: a "recent" shelf can't
    /// quietly age, and — because the date string ends up inside the query
    /// — the day's first request misses `ResponseCache` and goes to the
    /// network, instead of serving yesterday's front page for another
    /// 24 hours.
    static func daysAgo(_ days: Int) -> Date {
        Date(timeIntervalSinceNow: -Double(days) * 24 * 60 * 60)
    }
}
