# Networking and data flow

Four layers, each with one job. Views only ever call `PaperService`.

- `InspireHEPClient` (`Networking/InspireHEPClient.swift`): an `actor`
  wrapping `URLSession`, talking directly to `https://inspirehep.net/api`.
  No wrapper SDK. Pure HTTP — no caching, no app logic.
  INSPIRE enforces **15 requests / 5s per IP** (a blocked request still
  counts toward the quota), throttled client-side via a sliding timestamp
  window inside the actor, serialized for free by actor isolation.
  Both endpoints build their URL through one private `literatureURL`,
  which exists to hold a fix that must not apply to one and not the
  other: **`URLComponents` leaves a literal `+` in a query value alone,
  and the server reads `+` in a query string as a space.** INSPIRE was
  seeing `topcite 1000+` as `topcite 1000` and answering with papers
  cited *exactly* a thousand times — a silently wrong result, not an
  error. `percentEncodedQuery` is rewritten to escape it. Any future
  query operator containing `+` depends on this.
- `InspireRecord` (`Networking/InspireRecord.swift`): decodes INSPIRE's
  `{ id, metadata: {...} }` record shape — shared by search hits
  (`hits.hits[]`) and the detail endpoint — into a `Paper`, including
  turning `metadata.references[]` into lightweight `Paper`s. Kept out of
  the model so `Paper`'s own `Codable` stays the synthesized one, which
  is what lets the cache round-trip it. Known API quirks: the top-level
  `id` is a numeric **string** (e.g. `"3188089"`), not a JSON number
  (decode string-first with an `Int` fallback); a reference's `misc` is
  sometimes a bare `"[CMS]"` tag while the real title sits in
  `reference.title.title`, so `title` wins; entries that are only a
  `"[hep-th]"`-style tag with no author/record/DOI/URL are dropped.
  **A reference with a matched `record` is kept even with no title at
  all**, labelled by its journal line instead — older papers cite by
  journal rather than by title and INSPIRE stores them that way, so
  requiring a title silently emptied `references` for a whole era, taking
  the References carousel and `Recommender`'s `.sharedFoundations` edge
  down with it (that edge walks out through exactly these record ids).
- `PaperService` (`Networking/PaperService.swift`): the app's single
  entry point for paper data — `search`/`details`/`citations`/
  `references`, each 10 per page (`PaperService.pageSize`). Wraps the
  client with `ResponseCache` and **in-flight de-duplication** (the
  `Task` is registered in a dictionary before any `await`, so the same
  request asked for twice at once costs one trip). That's what makes
  overlapping loads safe: the detail screen and its References carousel
  both need the record, and opening "See All" re-asks for the page the
  carousel just showed.
  `references(of:page:size:)` also swaps each matched entry for its full
  record (concurrently, reassembled in order), since the embedded
  citation text has no abstract and is often mangled.
  Every method takes `refresh:` — pull-to-refresh has to drop the cache
  entry first or it silently answers from cache and looks broken. For
  references it re-fetches the source record only; the referenced papers
  didn't change because this one was pulled down, and refetching all ten
  would spend most of a rate-limit window. A refresh still joins an
  identical in-flight request rather than racing it.
- `ResponseCache` (`Persistence/ResponseCache.swift`): `actor`, memory
  dictionary in front of JSON files in `Caches/PaperResponses`, keyed by
  an FNV-1a digest of the request (`hashValue` is per-process seeded, so
  it can't name files that outlive a launch). `clear()`/`diskSize()` back
  the Settings screen's "Clear Cache".
  **Freshness and retention are two different clocks.** `lifetime` (24h)
  is how long an entry answers a request without going back to the
  network; `retention` (30 days) is how long it stays on disk at all, and
  `prune()` — which runs once at launch — uses the latter. They used to
  be the same constant, which quietly made the offline fallback below
  almost inert: prune ran at launch and deleted yesterday's entries
  before anything could fall back to them, which is exactly the case the
  fallback exists for. Disk space is `enforceBudget(protecting:)`'s job,
  not this one's.
  **A size budget on top of both clocks**, since a month of Home shelves
  is a lot of JSON: `enforceBudget(protecting:)` deletes oldest-first until
  the directory fits `ResponseCache.budget` (a `@AppStorage` Int, default
  500 MB, `0` meaning no limit; the Settings picker offers 50 MB – 1 GB).
  It runs at launch from `RootTabView`, whenever the picker changes, and
  after every 5 MB written — a whole-directory `stat` per store would be
  wasteful, but once a launch isn't often enough for a long session.
  **Protected keys go last and in practice never go at all**: the caller
  passes `ModelContext.cacheKeysWorthKeeping()`, the `detail|<id>` of
  every saved paper, which is what keeps the library readable offline.
  The list is built in `LibraryStore` rather than looked up here — a
  cache has no business reaching into SwiftData. Nothing here is
  irreplaceable either way; the library and history hold their own
  snapshots.
  **An aged-out entry is still served if the network is unreachable.**
  `papers(forKey:)` only returns entries under the 24h lifetime, but a
  request that ages out and then fails offline used to be a hard error
  even though a perfectly readable day-old copy sat right there.
  `PaperService` catches connectivity-shaped `URLError`s (`.isOffline` —
  not connected, DNS failure, timeout and similar; a real server answer
  like a 404 or a rate limit is left alone, so a stale copy can never
  mask one) and falls back to `stalePapers(forKey:)`, which is
  `papers(forKey:)` without the freshness check. Both go through one
  private `entry(forKey:)` so the two can't drift on where they look.
  A `refresh:` is excluded from the fallback: "show me this again, now"
  that can't reach the network should say so rather than re-serve what's
  already on screen.
  **A refresh skips the cache read rather than deleting the entry**, and
  that distinction is load-bearing. Deleting up front — which it used to
  do — threw the copy away before knowing a replacement was coming, so
  pulling to refresh with no signal destroyed the very entry that made
  the paper readable offline and then failed anyway. A successful `store`
  overwrites in place, so clearing first bought nothing. This is also why
  `remove(forKey:)` now has no callers; it's kept as a plain cache
  operation rather than removed.
- `PaperPager` (`Networking/PaperPager.swift`): drives infinite-scroll
  loading for any `List` of papers, a page at a time, more when the last
  loaded row appears. The page source is a closure, so a search query, a
  citations lookup and a reference list all page identically —
  `RelatedPapersDestination.makePager()` picks the right one.
  **`reload(using:)` is how a screen changes its source** — a new sort
  order, a new search query. It exists because building a fresh
  `PaperPager` and then calling `loadInitialIfNeeded()` leaves a render
  between the two where the new pager has nothing loading yet, which
  every list reads as "empty, not loading": a fast response then lands
  with no spinner ever shown. `reload` raises `isLoadingMore` before its
  first `await`, so the gap can't exist, and on `CancellationError` it
  deliberately leaves the flag up — the reload that superseded it is
  about to set its own state, and dropping it would blink the spinner off
  between two generations of one switch. Don't reintroduce
  "assign a new pager, then load"; three screens would each need to
  re-derive this. `reload(query:sort:)` is the overload views actually
  call — Search, an author's papers, New and a browse list differ only in
  the query string they hand it.
  **It no-ops when asked for the query it already has, and that's what
  keeps a reader's place.** `.task(id:)` re-runs every time its view
  re-appears, and popping a pushed paper back off counts as re-appearing
  — so returning from a detail screen used to wipe `papers`, reload page
  one, and drop the reader at the top of a feed they were twenty rows
  down. The `sort|query` marker is cleared when a load doesn't land, so a
  cancelled or failed one is retried on the next appearance rather than
  leaving a permanent spinner. `ExploreTabView`'s Trending task carries
  the same guard by hand (`guard trending.value == nil`). `refresh()`
  deliberately ignores the marker: "this same query, again" is exactly
  what pull-to-refresh means. `refresh()` backs `.refreshable` and resets
  paging state only once the new page is in hand: resetting up front and
  then failing would leave loaded rows next to a page counter pointing
  back at them, and the next scroll would append duplicate rows. Search
  and the "See All" lists are refreshable. Library and History aren't —
  they're local SwiftData, with nothing to pull for. **`PaperDetailView`'s
  `.refreshable` is inert and known to be: it's a `ScrollView`, which
  doesn't install a refresh control (confirmed on device). Left in place
  because it costs nothing and would start working if that changes; the
  "Try Again" button on the failed state is the real recovery path, and a
  record hardly changes anyway. Don't re-attempt by wrapping the screen
  in a `List` — that reintroduces the chevron/`NavigationLink` problems
  the carousels were moved out of a `List` to escape.**
- `LoadState<Value>` (`Utilities/LoadState.swift`): `loading` / `loaded`
  / `failed` for one-shot loads, replacing value + `isLoading` + error
  triples so "still loading" and "loaded but empty" can't drift apart.
  `LoadState.load { }` captures an operation's outcome and treats
  cancellation as still-loading (superseded `.task(id:)` generations
  aren't failures worth showing). `PaperDetailView` keeps three of these
  — record, references, citations — filled by three independent
  `.task(id:)` blocks, so the screen waits only on the record while each
  carousel shows its own spinner.
  `PaperPager.Phase` (`.idle`/`.loading`/`.failed`/`.empty`/`.content`)
  does the same job for a *paged* list: `isLoadingMore`/`loadError`/
  `reachedEnd` mean nothing individually, and every screen was deriving
  the same switch from the same three flags in the same order — the
  drift `LoadState` exists to prevent, in the paged case. `.idle` (nothing
  loaded, nothing in flight) renders as nothing, so a screen one frame
  before its `.task` runs doesn't flash a spinner; `.content` deliberately
  beats a `loadError`, so a failed page two doesn't blank page one. The
  shared rows that switch on it — `PagerLoadingRow`, `PagerFailureRow`,
  `PagerFooter` — live in `Views/Shared/PagerStateViews.swift`, used by
  `PapersListView` and `HeadlineFeedView`. New keeps its own row *layout*
  (it can't use `PapersListView` at all), so only these three are shared.
  The footer's `verticalPadding` is a parameter because New zeroes its
  `listRowInsets` and has to space itself; unifying it would silently
  respace every other list.
- **A rate limit is named apart from a network failure, everywhere.**
  `Error.isRateLimited` / `.loadFailureAdvice`
  (`Views/Shared/PagerStateViews.swift`) back every failure state in the
  app. INSPIRE caps at 15 requests / 5s and Home spends one per shelf
  while scrolling, so this is reachable in normal use — and "check your
  connection" is actively wrong advice for it. `PaperDetailView` (a
  `ScrollView`, so it keeps its explicit "Try Again") reads its wording
  from the same place.
