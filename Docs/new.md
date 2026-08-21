# New

The front page: what arrived, in the order it arrived. **The axis is
time and nothing on the screen ranks anything** — no sort control, no
search field, no "top story". The only choice is which corner of the
literature to watch, and it's the reader's explicit one.

- **A picker of chips at the top: All, then the twelve `ArxivCategory`
  values by their arXiv identifier** (`NewFeedSelection`). Stock capsule
  buttons — `.borderedProminent` for the one in effect, `.bordered` for
  the rest — because that's how Apple's own apps build a chip row. Two
  `if` branches rather than one styled button: the two styles are
  different types, so there's nothing to pick between in a single
  expression. It sits *above* the feed rather than scrolling with it, so
  switching corners never means scrolling back up first.
  The choice is remembered in `@AppStorage` as the raw id, and
  `NewFeedSelection(id:)` is total rather than failable — an id written
  by a build carrying a category this one doesn't falls back to All
  instead of leaving the tab empty. That single remembered choice solves
  the same cold start a multi-select "My Categories" would, and a feed
  retargetable in one tap doesn't also need a settings screen.
- **The feed is bounded to a rolling 14-day window
  (`NewFeedSelection.windowDays`), and that window is what keeps the tab
  fresh.** `ResponseCache` lives for 24h, so a New tab built on a
  timeless query would serve yesterday's front page all of today. The
  window's start date is *inside* the query string, so it moves at local
  midnight, the cache key moves with it, and the day's first look is a
  real fetch. Same trick as `BrowseTopic.trendingWindowStart`; both go
  through `Date.daysAgo(_:).inspireDay`
  (`Extensions/Date+Inspire.swift`), which also owns the two
  `DateFormatter`s the app parses INSPIRE dates with — held as statics
  because `Paper.formattedDate` runs once per row per render and a
  `DateFormatter` is expensive to build.
  Pull-to-refresh exists as well, but the window is what makes the tab
  right without anyone having to reach for it.
- **"All" is the union of the twelve categories, not an unfiltered
  query, and it has to be.** Asked for everything recent, INSPIRE leads
  with journal records whose `earliest_date` is a *future* month
  (month precision, no arXiv entry) — papers that aren't out yet and
  can't be filed under a day. Requiring an arXiv category is what makes
  every entry a dated preprint. The union has to be parenthesised:
  `de > X and A or B` binds the wrong way and would quietly return all of
  B, window or not. Expect the mix to be roughly a third quant-ph — the
  chips are the answer to that.
- **The layout is a newspaper page, and the rules between the columns
  are the entire design.** A horizontal rule under every row, a vertical
  one between columns, and nothing else: no fill, no border, no shadow.
  `HeadlineView` therefore carries only padding, and `HeadlineFeedView`
  draws every line. Rows are cut by hand rather than handed to
  `LazyVGrid`, because a grid gives nowhere to put a rule between
  columns (cells don't know their neighbours) and an `.adaptive` grid
  doesn't even know how many columns there are. A short last row is
  padded with `Color.clear` so its columns stay the width of every other
  row's, and gets no rule before the blanks — a line into empty space
  reads as a missing story.
- **The column count follows the measured width, not the size class:**
  one below 640pt, two below 960, three above, capped there
  (`NewTabView.minimumColumnWidth` = 320). The size class only knows
  "phone-ish" and "iPad-ish", so it has no way to say two, which is what
  an iPad in portrait wants. The width is read with `onGeometryChange`
  on the list rather than by wrapping it in a `GeometryReader` — no
  greedy layout container between the navigation stack and its list.

**Three container choices here are scar tissue. Each was a bug on
device, each cost a rewrite, and none of them is a style preference.**

- **A `List` — never `ScrollView` + `LazyVStack`.** A lazy stack has to
  *estimate* the height of rows it hasn't built and corrects the
  estimate the instant one materialises, so the content offset moves out
  from under the reader: the first page-two load blanked the screen, and
  scrolling back up threw the reader to the bottom, every time. **Pinning
  each headline to a fixed height did not fix it** — the estimate is made
  before the view exists, so there is nothing to ask. `List` is
  `UICollectionView` underneath: it anchors the visible rows when a cell
  resizes and reuses cells instead of rebuilding them. Every other
  paginated screen here is a `List` carrying the same
  asynchronously-measured `MathTextView`s and none has ever had this
  problem; New was the only one that wasn't.
  What `List` was avoided for is handled rather than traded away: there
  are no `NavigationLink`s in the feed at all, just `Button`s appending
  to the `NavigationPath` `NewTabView` owns, so there are no sibling
  links to mis-manage and no row to staple a chevron onto. Rows run edge
  to edge (`.listRowInsets(EdgeInsets())`) with the system separators
  hidden. Pull-to-refresh comes back for free.
- **Flat day-header rows — never `Section`.** `Section` brought two more
  bugs, both long-reported and still open upstream: ghost separator
  lines at section boundaries that no combination of
  `.listRowSeparator(.hidden)` / `.listSectionSeparator(.hidden)`
  suppresses, and `onAppear` on a row *inside* a `Section` not firing
  reliably even when the row is genuinely on screen. The second silently
  stalled pagination on hep-th while hep-ex kept paging, with no error
  shown anywhere. The cost of flattening is that day headers no longer
  pin while scrolling. **If a ghost line or a stalled loadMore ever
  reappears, look for whatever introduced a `Section` first.**
  `HeadlineFeedView` also keeps `sentinel`, a 1pt invisible row after the
  last day, as a second pagination trigger — the underlying `onAppear`
  unreliability isn't `Section`-specific enough to trust one trigger.
- **`Rectangle` rules — never `Divider()`.** `Divider()` picks its
  orientation from the stack it is a *direct* child of, and the
  between-column rule sits behind `if index > 0`, which wraps it in
  `_ConditionalContent` and loses that context; it fell back to
  horizontal. Inside a `List` row that surfaced as a cluster of stray
  horizontal lines under each day, one per gap between columns, inert to
  the touch. A `Rectangle` has no orientation to infer. **If a rule ever
  moves back to `Divider()`, keep it an unconditional direct child of its
  stack — never behind an `if`.**

- **Every headline is a fixed height** (`HeadlineView.cellHeight`): the
  rule under a row of three stops at one distance rather than three, the
  collection view never has to re-measure a cell, and a plot-less
  headline can be filled out instead of left hollow. `@ScaledMetric`
  keeps it honest under Dynamic Type, the reserve is deliberately
  generous (KaTeX line boxes are taller than plain text), slack collects
  in one `Spacer` above the footer, and `.clipped()` is the backstop.
- A headline shows one plot, `Paper.headlineFigure` — the *last* figure,
  since INSPIRE lists them in the paper's own order and the last is
  usually the result rather than the apparatus schematic the first
  usually is. Search hits already carry `metadata.figures[]`, so the
  image costs no extra request. Fixed height rather than an aspect ratio,
  for the reason `FigureCarouselView` fixes its card size. Most hits
  have one.
- **A headline with no plot gets the abstract lines the plot would have
  taken**, which is also how the two variants come out the same height.
  The extra count is rounded *down* and less two lines' margin:
  overshooting is the one way this layout breaks, because the surplus
  pushes the footer past the clip and out of the box, where slack merely
  sits under the abstract.
- **The abstract runs to six lines** (`HeadlineView.abstractLines`),
  against `PaperRowView`'s two. That's the point of the screen — a search
  result is something you scan past, a front page is something you read.
  Six is what the web version of this feed uses.
- Day sections come from `[Paper].groupedByDay()`, which groups
  *contiguous* runs rather than sorting: `mostrecent` already returns
  non-increasing dates, so a page loaded later just extends the day it
  fell in. `PaperDay.title` checks the component count before parsing,
  because `yyyy-MM-dd` will happily read INSPIRE's month-precision
  "2026-12" as the first of December; a date it can't place to the day is
  shown as INSPIRE wrote it.
- Tapping a headline appends `ZoomedPaper` to the path, so the block
  grows into the detail screen the way a card does — once headlines
  became fixed-height boxes fenced in by rules they *are* the bounded
  objects the zoom asks for. The source is the whole block, never a part
  of it (see `paperTransitionSource`); `.zoom` pairs with a programmatic
  push exactly as it does with a `NavigationLink`.
