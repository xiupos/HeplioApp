# Library, history, and search history (SwiftData)

Three stored models in `Persistence/`, registered together in
`LibraryStore.models` and installed by `.modelContainer(for:)` in
`HeplioApp`. All reads and writes go through the helpers in
`LibraryStore.swift`'s `ModelContext` extension, so de-duplication and
trimming live in one place rather than in each view.

- **Saving is one flat list.** `SavedPaper`, no folders, collections, or
  tags. The Library tab sorts it with `LibrarySort` (Recently Saved /
  Title / Year / Citations as Saved) and filters it with a `.searchable`
  field over title and first author.
- **The sort and filter are in the `@Query`, not applied afterwards.**
  `@Query` is configured at init and can't be re-pointed, so the query
  lives in a private `SavedPapersList` child that `LibraryTabView`
  re-initializes with the current sort and filter. Sorting rows in memory
  instead would mean decoding every snapshot on every keystroke.
- **That's why the queryable fields are stored columns, duplicated out of
  the snapshot.** SwiftData can't see inside the JSON, so `title`,
  `firstAuthor`, `year` and `citationCount` are real properties on both
  `PaperRecord` models, written by `applyMetadata(from:)`.
  `ModelContext.backfillPaperMetadata()` (run once from `RootTabView`'s
  `.task`) fills them in on rows written before they existed — it selects
  on `firstAuthor.isEmpty`, so it finds nothing from the second launch
  on. `RootTabView` reads the context, not `HeplioApp`: the container is
  installed on the scene, so the `App` itself is outside it.
- **`citationCount` is frozen at save time** and the menu says so
  ("Citations as Saved"). A paper saved at 10 citations still reads 10 a
  year later. Re-fetching the library to freshen it would spend the whole
  rate-limit window every time the tab opens; `title`, `firstAuthor` and
  `year` don't have this problem because they don't change.
- `ViewedPaper` is the history behind the Library toolbar's clock button
  (`HistoryView`, a sheet with its own `NavigationStack`). One entry per
  paper — a revisit updates the timestamp rather than appending — capped
  at `ViewedPaper.limit`. Opening a paper from there pushes inside the
  sheet, which is convenient but cramped compared to the tab's own full
  width; `PaperDetailView` shows an "Open in Library" toolbar button
  there (via `EnvironmentValues.openInLibrary`, set only by
  `LibraryTabView`'s sheet) that dismisses the sheet and pushes the same
  paper onto the Library tab's own `NavigationStack` (kept as explicit
  `@State private var path: NavigationPath` for exactly this reason). Its
  `fromSearch` flag is what the Search tab's "Recently Opened" section
  queries on, so that section means "found by searching", like Music's.
  The flag is set from `EnvironmentValues.paperOrigin`, which
  `SearchTabView` puts on its `NavigationStack`; a shared row view
  shouldn't have to pass along which tab it's in.
- `RecentSearch` backs "Recently Searched", recorded on
  `.onSubmit(of: .search)` (not per keystroke), capped at
  `RecentSearch.limit`.
- Both `SavedPaper` and `ViewedPaper` keep a JSON `snapshot` of
  `Paper.summary` — the row-sized copy, with the bibliography dropped and
  authors capped at 4 (one past what a row shows, so "et al." still
  renders) — a large reduction from the full record. The detail screen
  always refetches the full record, so nothing is lost by storing less.
- **Two traps already hit here, don't reintroduce:**
  `FetchDescriptor.fetchOffset` without a `fetchLimit` came back as every
  row, so the "keep the newest N" trim deleted each entry as it was
  recorded (history, recent searches and "Recently Opened" all silently
  stayed empty while saving, which has no trim, worked) — skip in memory
  with `dropFirst(limit)` instead. And `.environment(...)` has to go on
  the `NavigationStack`, not on a view inside it, or pushed destinations
  never see it.
- **Designed for iCloud sync, not yet turned on.** Every property has a
  default value, nothing uses `@Attribute(.unique)` (CloudKit forbids
  unique constraints — hence de-duplicating by fetch in
  `recordView`/`recordSearch`), and there are no relationships. Enabling
  it should be an iCloud container plus
  `ModelConfiguration(cloudKitDatabase:)` in `LibraryStore`. Keep new
  models to these rules. `ResponseCache` deliberately stays local — it's
  a cache, not user data. **The recommendation layer adds nothing here on
  purpose**: `ReadingProfile` is recomputed from these three models rather
  than stored, so there are still exactly three things to sync — see
  [Home, and the recommendation function](home-and-recommendation.md).
