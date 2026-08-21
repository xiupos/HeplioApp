# Author pages

Tapping the author names on `PaperDetailView` opens one author's papers
(`Views/Author/`). An author lookup is just another INSPIRE query, so
`AuthorPapersView` is the same `PaperPager` + `PapersListView` as Search
and shares its cache entries — there's no separate service method.

- `Paper.Author.papersQuery` prefers `authors.recid:<id>`, INSPIRE's
  disambiguated author record, over a name match — a name match pulls in
  other people's papers too. Every author of a curated record has one, so
  the `a <name>` fallback is rare.
- Author count drives the whole interaction, at
  `PaperHeaderView.inlineAuthorLimit` (10): one author is a plain
  `NavigationLink`, up to ten open a `Menu` of them, and beyond that the
  header truncates with a "Show All N Authors" link to `AuthorListView`
  — pushed and searchable, the way INSPIRE's own site handles it.
- **Every author push is a `NavigationLink` to a destination registered
  in `paperNavigationDestinations()`, and it has to stay that way.** Two
  bugs came from doing otherwise: a `confirmationDialog` anchored its
  iPad popover to the middle of the screen instead of the names (a
  `Menu` anchors to its own label), and a
  `.navigationDestination(item:)` declared on `PaperDetailView` — an
  already-pushed view — made pushes from the screens beyond it grow the
  back stack without changing what was on screen. Destinations belong on
  the stack's root.
- `AuthorListDestination` carries the record id, not the authors: it's a
  navigation value, so it gets hashed on every path change, and
  `AuthorListView` re-reads the record from the cache instead (a cache
  hit even for thousands of authors, since the detail screen just loaded
  it).
- The header shows `Author.nameWithAffiliation` — INSPIRE already
  publishes affiliations in short form ("DESY", "Madrid, IFT"), so
  they're used as given; only the first is shown per author.
