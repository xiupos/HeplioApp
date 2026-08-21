# Sorting

Search, an author's papers, every Explore browse list, and the Library
share one control: `.sortToolbarItem($sort, options:)`
(`Views/Shared/SortMenu.swift`), generic over a `SortOption` — the
protocol exists so the two unrelated orderings in the app
(`InspireHEPClient.SortOrder`, which ranks an INSPIRE query, and
`LibrarySort`, which is a `SortDescriptor` over SwiftData columns) get
one menu instead of two that drift apart.

For the INSPIRE screens the whole thing is two lines:
`.sortToolbarItem($sort, options:)` and
`.task(id: sort) { await pager.reload(query:sort:) }`. Everything
subtle — the loading-state gap, cancellation — lives in
`PaperPager.reload`, not in each screen.

- **`InspireHEPClient.SortOrder.relevance` means "send no `sort`
  parameter at all"** — that's how INSPIRE returns its own text ranking,
  and there is no word for it. Don't invent one: INSPIRE **silently
  ignores** sort values it doesn't recognize (`sort=garbage123` returns
  HTTP 200, relevance-ordered), so a guessed `bestmatch` would look like
  it worked whether or not it did. `queryValue` returns nil for this case
  and `literatureURL` drops the item. `rawValue` stays `"relevance"` so
  the cache key remains distinct.
- **Search defaults to relevance, and must.** It used to hardcode
  `.mostRecent`, which meant "dark matter direct detection" — nearly
  9,000 hits — opened on yesterday's uncited preprints instead of the
  canonical papers.
- **Browse screens don't offer relevance** (`[SortOrder].browseOptions`).
  `authors.recid:1234` and `primarch hep-th` match every hit equally, so
  there's nothing for a text ranking to rank. The two option sets are
  declared on `Array where Element == SortOrder`, not on the enum:
  `sortToolbarItem(_:options:)` takes `[SortOrder]`, and leading-dot
  syntax resolves against the parameter's own type, so statics on the
  element are invisible there.
- Search debounces on the query text only, not on the sort — a 400 ms
  wait after tapping a menu item reads as broken. Both feed one
  `.task(id: Request(query:sort:))`, since two separate `.task(id:)`
  blocks would each fire on appear and load the same page twice.
- **`pagedPapersList(_:)` carries chrome only — flat rows and
  pull-to-refresh — never loading.** It used to bundle a one-shot
  `.task { loadInitialIfNeeded() }`, which silently did the wrong thing
  for any screen with a sort control, so each call site now states its
  own policy: `.task { loadInitialIfNeeded() }` for a fixed source
  (`RelatedPapersListView`), `.task(id: sort) { reload(query:sort:) }`
  for the rest. Don't put loading back in.
