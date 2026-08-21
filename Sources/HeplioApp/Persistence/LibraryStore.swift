import Foundation
import SwiftData

/// The app's stored data: bookmarks, history, recent searches.
///
/// Designed to be turned on for CloudKit later without a migration — every
/// property has a default value, nothing is `@Attribute(.unique)` (CloudKit
/// doesn't support unique constraints, so de-duplication happens in
/// `ModelContext+Library` instead), and there are no relationships to make
/// optional. Switching over means adding an iCloud container and
/// `ModelConfiguration(cloudKitDatabase: .automatic)` here, nothing more.
enum LibraryStore {
    static let models: [any PersistentModel.Type] = [
        SavedPaper.self,
        ViewedPaper.self,
        RecentSearch.self
    ]
}

// MARK: - Reads and writes

extension ModelContext {
    // MARK: Saved

    func savedPaper(id: Int) -> SavedPaper? {
        let descriptor = FetchDescriptor<SavedPaper>(predicate: #Predicate { $0.paperID == id })
        return try? fetch(descriptor).first
    }

    /// Bookmarks the paper, or removes the bookmark if it's already there.
    func toggleSaved(_ paper: Paper) {
        if let existing = savedPaper(id: paper.id) {
            delete(existing)
        } else {
            insert(SavedPaper(paper: paper))
        }
    }

    // MARK: History

    /// Records a visit, folding it into the paper's existing entry so the
    /// list reads as "papers, most recent first" rather than repeating one
    /// paper the reader keeps coming back to.
    func recordView(of paper: Paper, fromSearch: Bool) {
        let id = paper.id
        let descriptor = FetchDescriptor<ViewedPaper>(predicate: #Predicate { $0.paperID == id })
        if let existing = try? fetch(descriptor).first {
            existing.viewedAt = .now
            existing.fromSearch = fromSearch
            existing.snapshot = PaperSnapshot.encode(paper)
            existing.applyMetadata(from: paper)
        } else {
            insert(ViewedPaper(paper: paper, fromSearch: fromSearch))
        }
        trim(ViewedPaper.self, sortedBy: \.viewedAt, to: ViewedPaper.limit)
    }

    func clearHistory() {
        try? delete(model: ViewedPaper.self)
    }

    // MARK: Recent searches

    func recordSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let descriptor = FetchDescriptor<RecentSearch>(predicate: #Predicate { $0.text == trimmed })
        if let existing = try? fetch(descriptor).first {
            existing.searchedAt = .now
        } else {
            insert(RecentSearch(text: trimmed))
        }
        trim(RecentSearch.self, sortedBy: \.searchedAt, to: RecentSearch.limit)
    }

    func clearRecentSearches() {
        try? delete(model: RecentSearch.self)
    }

    // MARK: Reading signals

    /// Everything the reader has done with a paper, as the plain values
    /// `ReadingProfile` folds into a taste profile.
    ///
    /// Both tables whole, every time. They're capped at a hundred visits
    /// and however much someone bookmarks, and the snapshots are the
    /// row-sized copies — so this is a few hundred small JSON decodes,
    /// which is the entire reason the profile can be recomputed on every
    /// appearance instead of being stored and synced.
    private func readingSignals() -> [ReadingSignal] {
        let saved = (try? fetch(FetchDescriptor<SavedPaper>())) ?? []
        let viewed = (try? fetch(FetchDescriptor<ViewedPaper>())) ?? []
        return saved.compactMap { record in
            record.paper.map { ReadingSignal(paper: $0, isSaved: true, date: record.savedAt) }
        } + viewed.compactMap { record in
            record.paper.map { ReadingSignal(paper: $0, isSaved: false, date: record.viewedAt) }
        }
    }

    /// What this reader is interested in, folded out of the library and
    /// the history.
    ///
    /// The one place the two are turned into a profile, so Home and the
    /// detail screen's Related carousel can't end up ranking against
    /// subtly different inputs. Nothing is cached: see `ReadingProfile`
    /// for why recomputing is the point rather than a cost.
    func readingProfile() -> ReadingProfile {
        ReadingProfile(signals: readingSignals())
    }

    /// Bookmarked papers, most recently saved first — what Home's "From
    /// Your Library" shelf draws from.
    func savedPapers() -> [Paper] {
        let descriptor = FetchDescriptor<SavedPaper>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        return ((try? fetch(descriptor)) ?? []).compactMap(\.paper)
    }

    /// Papers opened but never bookmarked, most recent first. The ones a
    /// reader passed through and might mean to come back to — which is
    /// exactly the set a "Read Again" shelf is for, and why it excludes
    /// the saved ones rather than repeating the Library.
    func unsavedViewedPapers() -> [Paper] {
        let descriptor = FetchDescriptor<ViewedPaper>(sortBy: [SortDescriptor(\.viewedAt, order: .reverse)])
        let saved = Set(((try? fetch(FetchDescriptor<SavedPaper>())) ?? []).map(\.paperID))
        return ((try? fetch(descriptor)) ?? [])
            .filter { !saved.contains($0.paperID) }
            .compactMap(\.paper)
    }

    /// The `ResponseCache` keys worth keeping when the cache is over
    /// budget: the detail record behind every saved paper, which is what
    /// lets the library open without a network round trip.
    ///
    /// Built here rather than inside `ResponseCache` because the cache
    /// shouldn't know SwiftData exists. The key format has to match
    /// `PaperService.details(id:)`, which is the one thing tying the two
    /// together.
    func cacheKeysWorthKeeping() -> Set<String> {
        let saved = (try? fetch(FetchDescriptor<SavedPaper>())) ?? []
        return Set(saved.map { "detail|\($0.paperID)" })
    }

    // MARK: Migration

    /// Fills in the columns added for the Library's sort menu on records
    /// written before they existed. SwiftData gives those rows the
    /// property defaults, so they'd otherwise all sort as year 0 with no
    /// author — which looks like data loss even though the snapshot has
    /// had it all along.
    ///
    /// Cheap and self-limiting: it only decodes rows that still look
    /// unfilled, so the pass finds nothing from the second launch on.
    /// Runs at launch alongside the cache prune.
    func backfillPaperMetadata() {
        backfill(SavedPaper.self)
        backfill(ViewedPaper.self)
    }

    private func backfill<T: PaperRecord>(_ model: T.Type) {
        // Filtered in Swift, not with a `#Predicate`: the predicate would
        // have to be written against the generic `T`, and SwiftData
        // resolves a protocol-witness key path to no column it knows.
        // These tables are small and this reads every row once per
        // install, so there's nothing to win by pushing it down.
        //
        // `firstAuthor` is the marker rather than `year`, because a
        // genuinely year-less record exists while every record worth
        // showing credits someone.
        guard let all = try? fetch(FetchDescriptor<T>()) else { return }
        for entry in all where entry.firstAuthor.isEmpty {
            guard let paper = entry.paper else { continue }
            entry.applyMetadata(from: paper)
        }
    }

    /// Drops everything past the newest `limit` entries. Skips in memory
    /// rather than with `FetchDescriptor.fetchOffset`, which is unreliable
    /// without a matching `fetchLimit` — it came back as "every row", so
    /// this deleted each entry the moment it was recorded. These lists are
    /// capped at a hundred entries; fetching them whole costs nothing.
    private func trim<T: PersistentModel>(
        _ model: T.Type,
        sortedBy keyPath: KeyPath<T, Date> & Sendable,
        to limit: Int
    ) {
        let descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(keyPath, order: .reverse)])
        guard let entries = try? fetch(descriptor), entries.count > limit else { return }
        for entry in entries.dropFirst(limit) { delete(entry) }
    }
}
