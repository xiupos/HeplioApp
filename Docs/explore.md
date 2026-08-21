# Explore

A browsable catalog with **no algorithm and no user state** — Search's
counterpart, and the reason Explore could ship before any recommendation
work exists. Everything on it is a static shelf over a dynamic INSPIRE
query.

- **The shelves are hard-coded, and have to be.** The API returns no
  facets (see [INSPIRE query syntax](query-syntax.md)), so there is no
  list to fetch them from. `BrowseTopic` (`Views/Explore/BrowseTopic.swift`)
  holds the curation: `ArxivCategory.allCases`, 16 collaborations whose
  names were each checked against `collaboration:"…"` (INSPIRE's
  spelling isn't always the obvious one — "Belle-II", "LIGO
  Scientific"), and three collections (`tc r` / `tc l` / `topcite
  1000+`). Collaboration tiles carry a hand-written facility line
  ("CERN, LHC", "South Pole") — the one piece of curation not derivable
  from the API, and worth it: sixteen bare acronyms are a dropdown,
  sixteen with places attached are somewhere to wander.
- **Opens with papers, not a table of contents.** Music's Browse doesn't
  start with genre names and News doesn't start with topic names. The
  Trending shelf is `de > (60 days ago) and topcite 5+` sorted by
  citations — recent work that is *already* being cited. No inference and
  no editorial pick: the citations are real, which is exactly why this
  belongs on Explore while a "top story" slot doesn't belong on New. It's
  the one request the tab costs, `BrowseTopic.trendingWindowStart` moves
  once a day, and everything below it is static.
- **A `ScrollView`, not a `List`** — the same structure as
  `PaperDetailView`, for the same reason. Every tile and every carousel
  card is a `NavigationLink`, and a `List` row holding several siblings
  mis-manages them and staples its own disclosure chevron onto each. Not
  using a `List` is also what lets `PaperCarouselView` be reused here
  at all.
- **Grids, not rows.** `LazyVGrid(.adaptive(minimum: 150))` gives two
  columns on iPhone and four or five on iPad. These are peers, not a
  settings menu, and a linear list draws one 900-point-wide row per
  category on an iPad. Don't reach for `NavigationSplitView` for the
  two-column effect — it fights the outer `.sidebarAdaptable` sidebar.
- `BrowseTileView` deliberately reuses `PaperCardView`'s exact material
  so the carousel and the grids read as one screen made of one thing. It
  adds no design vocabulary; it's the already-documented card exception
  with a label in it. Fixed minimum height, because tiles whose subtitle
  wraps ("T2K to Super-Kamiokande") would otherwise sit at ragged heights
  across a row.
- **Every shelf entry is one navigation value opening one screen.**
  Because a category, an experiment and a document type all reduce to a
  `q=` string, `BrowseListView` handles all three; adding a shelf is a
  case on `BrowseTopic`, not a new view. `BrowseTopic` is registered in
  `paperNavigationDestinations()` rather than in `ExploreTabView` alone —
  New pushes topics too, and a paper's category kicker links one from.
- `ArxivCategory` (`Models/ArxivCategory.swift`) carries **two queries
  per category, deliberately**: `browseQuery` (`primarch hep-th`, primary
  category only) for Explore, where the point is the character of the
  field, and `feedQuery` (`arxiv_eprints.categories:hep-th`, cross-lists
  included) for New, where a cross-listed paper is something the reader
  wants. It also owns the category display names, which `Paper.kicker`
  reads.
- **`BrowseListView` doesn't use `pagedPapersList(_:)`**, though it looks
  like it should. That modifier bundles a one-shot
  `.task { loadInitialIfNeeded() }`, and changing the sort has to build a
  new pager (the sort is captured in the fetch closure), which the
  one-shot task would never load. It rebuilds on `.task(id: sort)`
  instead — the shape `SearchTabView` already uses for a changing query.
  Switching sort replaces the pager outright rather than re-sorting
  loaded rows: the ordering is INSPIRE's, and page 4 of "most cited" has
  nothing to do with page 4 of "most recent".
- Sort is view state, not a preference. A browse screen is somewhere you
  pass through, so each push starts at `topic.defaultSort` — Most Recent
  for the shelves that mean "what's new in this corner", Most Cited for
  Trending and Landmarks, where a date ordering would be nonsense.
