# Home, and the recommendation function

Home is *you*. Everything on it is keyed to what this reader has read,
which is what keeps it from collapsing into Explore — and the two
impersonal shelves that do appear (Trending, "New This Fortnight") are
deliberately kept out of the top of the screen for exactly that reason.

The whole feature is `Recommendation/` (three `Foundation`-only files)
plus `Views/Home/`. It backs two screens: Home's shelves and
`PaperDetailView`'s Related carousel. **One function, built general from
the start** — *given a set of papers, return ranked related ones* — since
a Related-only shortcut would have had to be thrown away the moment Home
needed the same thing over a library.

## Nothing derived is ever stored, and that's the design

The SwiftData store is destined for iCloud. Syncing an algorithm's
scratch paper — profiles, "already featured" lists, scores — means
migrations and merge conflicts for data that can be recomputed in
milliseconds. So none of it exists.

- **`ReadingProfile` is a fold over the library and the history**, rebuilt
  on each Home appearance from `ModelContext.readingSignals()` (wrapped
  by the public `readingProfile()`). A few hundred rows of row-sized
  snapshots; cheap enough that storing it would cost more than
  recomputing it. A fresh device gets the right Home the moment the
  records land, with nothing to migrate.
- **Day-to-day variety is a pure function of the calendar day**, not
  stored state: `DailySeed` is FNV-1a over `localDay + a per-shelf salt`,
  driving a SplitMix64 `RandomNumberGenerator`. Stable however often the
  app is reopened that day, different tomorrow, and identical on two
  devices that never exchanged a byte about it. `String.fnv1aHash`
  (`Utilities/FNV1a.swift`) is shared with `ResponseCache`'s file naming
  for the same reason both need it: `hashValue` is seeded per process.
- **Repeat suppression rides on `ViewedPaper`.** Instead of remembering
  what Home has featured, a paper the reader has *opened* is excluded
  from every discovery shelf and appears only on the re-read shelves. The
  store already keeps that fact and will already sync it. A
  recommendation the reader ignores can come back — ignoring isn't
  rejecting, and the App Store behaves the same way.

## The two edges, and why there are two

`Recommender.Edge` picks which citation edge to walk. Both are **one
request**, because INSPIRE performs the join: a whole reading profile is
one `or` of `refersto` clauses.

- `.citingWork` — `(refersto:recid:S1 or …) and de > <180d>`, papers that
  *cite* the seeds. "What's new that builds on what you read." Home's
  "For You".
- `.sharedFoundations` — `(refersto:recid:R1 or …) and not recid:X`,
  where the `R` are the seed's own references: papers built on the same
  foundations, i.e. siblings rather than descendants. **A single paper's
  "Related" has to use this one**, because for one paper
  `refersto:recid:X` is *already* the Cited By carousel sitting next to
  it. The references come free from the cached detail record, ranked by
  title overlap with the source so the anchors are the real foundations
  rather than the hat-tips (a software citation, the PDG).

**Candidates are always re-ranked against the seeds, not just the
reader** (`Recommender.related`'s `subject` profile). Skipping this was a
real bug: with an empty reader profile the only surviving signal is the
citation prior, and a citation prior on its own doesn't return related
papers, it returns famous ones — asked for work related to Maldacena's
AdS/CFT paper it answered with the *Review of Particle Physics*. With the
seed profile blended in it answers with Gubser-Klebanov-Polyakov and
Strominger-Vafa, which is right.

**`Recommender.candidatePoolSize` is wide, not the smaller number it
started at.** A narrower pool sorted by citations converges on the same
handful of "canonical" landmark papers for almost any query in a
subfield — a heavy reader who has already opened enough of that
recurring canon (e.g. all of Michael Douglas's string-theory papers) can
exhaust a small pool entirely and see "No Related Papers" for a paper
that genuinely has one. Widening the pool keeps enough headroom for local
exclusion (already-read/-saved) to still leave real candidates.

**`ReadingProfile.score` is ordering only; eligibility is
`Recommender`'s.** Score once returned 0 for "already seen" and
`Recommender` filtered on `score > 0` — but zero is a legitimate score
(an uncited preprint under an empty profile earns exactly it), so that
silently dropped every new paper for a first-launch reader. Read/saved/
seed exclusion is now stated explicitly where the filtering happens.

**An empty result renders as nothing, not a placeholder card.** The
Related carousel simply doesn't appear when there's nothing to show,
the same as References/Cited By — a heading that quietly disappears
beats a card that exists only to say there's nothing in it.

## INSPIRE keywords, and why they can't be the only signal

`Paper.keywords` carries INSPIRE's subject terms; `topicalKeywords`
filters them. Two facts about the data decide how they're used:

- **The vocabulary contains structural markers, and they're among the
  most common values in it** — "experimental results", "bibliography",
  "numerical calculations", "review". Left in, they'd be the top "topic"
  for most readers while saying nothing about subject matter.
  `Paper.structuralKeywords` drops those, plus anything ending in
  " Coll" ("CERN LHC Coll") — that axis is `BrowseTopic.collaboration`'s
  job and it does it properly.
- **Curation runs about two years behind.** INSPIRE-schema keywords cover
  essentially all older papers and almost none from the last two years.
  Recent papers carry only free-form author keywords (a minority, no
  `schema`), which are inconsistent — "holography" beside
  "Gauge-Gravity Correspondence". Both kinds are taken. This is why
  `ReadingProfile.score` keeps its category term alongside the keyword
  one: for a paper too new to be indexed, the category is all there is.
  It's also why keyword *queries* still work for recent material —
  `k "AdS/CFT correspondence"` sorted `mostrecent` still returns current
  papers.

Keywords come free: search hits carry them without a `fields` parameter,
so no shelf costs an extra request. They're kept in `Paper.summary`
because a library storing only categories could only ever recommend by
category.

**`Paper.keywords` is `[String]?`, and must stay optional.** `Paper`'s
`Codable` is synthesized, and a synthesized decoder throws `keyNotFound`
for a missing non-optional — a default value does *not* rescue it. Every
`SavedPaper`/`ViewedPaper` snapshot already on disk predates the field,
so a non-optional here would fail to decode the reader's whole library.
The same applies to any future field.

Other scoring notes: weight is `base × exp(-ageDays / 30)`, saved `1.0`
against viewed `0.6`, and a paper in both tables counts once at the
heavier weight. Each facet's weight is divided across the paper's own
keys, so a huge-author collaboration record doesn't hand every author a
full vote. The stopword list is tiny and physics-blind on purpose:
"measurement", "search", "effective", "model" look like filler in English
and are exactly what separates an experimental paper from a theory one
here.

## The shelves, and the infinite stream

**Home scrolls as far as there is material, and it's the shelf *list*
that paginates**, not the papers in any one shelf. `HomeShelfStream` is a
pure `(profile, preferredCategory, day) -> [HomeShelf]`, built whole
(bounded by the library, the history and the `BrowseTopic` catalog), so
paging is a `prefix` and the end is known.

- **A fixed spine, then a day-rotating stream.** `For You` and `Because
  You Read X` always lead — a tab whose first row moves around is one you
  have to re-read every morning. What changes daily is *which paper* `X`
  is, drawn by `DailySeed` from the top 30 seeds, so the shelf's own
  title is different each day.
- **The rotation alternates local, network, local, network — local
  first.** Local shelves (`readAgain`, `fromLibrary`, the two tile grids)
  cost nothing; the rest cost a request each. Local first because the
  spine is itself two network shelves, and opening the rotation with a
  third would put the worst burst of the whole screen where every reader
  meets it. One local per network rather than two, because local shelves
  are the scarcer resource — bounded by how much the reader has actually
  read — and spending them singly doubles the protected stretch.
  **The guarantee ends when the local queue runs dry** and the tail is
  network-only; that's fine because `InspireHEPClient.throttle()` blocks
  rather than fails at 15 req/5s, so a fast scroll down the tail is slow,
  not broken.
- **Local shelves are sliced by category** — "Read Again · Cosmology",
  "From Your Library · Theory". Repeating one title four times is a bug
  report; slicing is also what makes them deep enough to scroll.
- **Topic shelves are INSPIRE keywords first, arXiv categories last**
  (`HomeShelfStream.interestTiers`). A category is far too coarse to be
  "a topic you're interested in" — two hep-th readers can be in entirely
  different worlds, and a shelf called "Theory" tells someone nothing.
  `BrowseTopic.keyword` queries `k "field theory: conformal"`, INSPIRE's
  own indexing vocabulary. Categories stay on the end rather than being
  dropped because keyword coverage isn't universal — see "INSPIRE
  keywords" above. **The tiers are shuffled within themselves, never
  across**: the shuffle is for daily variety, and shuffling the
  *flattened* list silently throws the whole ordering away. That mistake
  was made twice — once in `topicShelves`, then again independently in
  the tile grid. Both go through `shuffledInterests(of:dice:)` now, so
  there is no correct-looking way left to write it wrong.
- **A shelf that comes back empty renders as nothing.** The stream can't
  know the reader has nothing saved under `hep-lat`. The row survives (it
  carries the pagination trigger) but the spacing lives *inside* it, so an
  empty shelf leaves no gap.
- **The cold start is Explore-lite, never an empty state**, ordered with
  the New tab's `@AppStorage("newFeedSelection")` chip first — the one
  interest the reader states out loud rather than one this app infers. A
  footer says what would change; the screen itself is already full.
- Two shelves reuse another tab's query string *exactly*
  (`NewFeedSelection.all.query`, `BrowseTopic.trending.query`), so they
  are `ResponseCache` hits rather than second requests for the same
  thing.
- Every "See All" pushes a value already registered in
  `paperNavigationDestinations()` — `RelatedPapersDestination`,
  `Paper.Author`, `BrowseTopic`. Home adds no destination of its own.

## Container choice: a `List`, like New

Home paginates, so it takes New's side of the argument rather than
Explore's, for the same reason: `ScrollView` + `LazyVStack` drags the
content offset out from under the reader as it corrects its row-height
estimates. The standing objection to a `List` — it mis-manages sibling
`NavigationLink`s in a row and staples chevrons onto them — is answered
the way New answered it: **there are no `NavigationLink`s on Home at
all**, only `Button`s appending to the tab's own `NavigationPath`.

That's what `PaperCarouselView`'s `onSelect` / `onSeeAll` are for. When
they're set the cards and the header become `Button`s; when they're nil
the existing `NavigationLink` path is untouched, so Explore and
`PaperDetailView` are unaffected. The `Destination == AnyHashable`
convenience init exists only because Swift can't default a generic
parameter at a call site that never mentions one.

**The footer spinner deliberately does not also trigger the next page**,
the way New's sentinel row does. Revealing more shelves makes the footer
re-appear a moment later, so one scroll to the bottom would cascade into
revealing the whole stream and firing every request in it at once. The
last shelf's own `.onAppear` is the single trigger and advances one page
per render — including through shelves that turn out to be empty, since
the next one then becomes the last.

`.task` on the tab is guarded (`guard stream == nil`) for the reason
`PaperPager.reload` and Explore's Trending task are: `.task` re-runs on
every re-appearance and popping a paper back off counts, so rebuilding
there would re-deal the screen under a reader on their way back to where
they were.

Pull-to-refresh rebuilds the profile and bumps a `reloadToken` that each
shelf passes to `PaperService` as `refresh:`. The shelf *order*
deliberately doesn't change — it's a function of today's date, and today
is the same after a pull as before it. What refreshes is what's on the
shelves. `HomeShelfView` tells a first load from a refresh with
`loadedToken`, so a row built late doesn't refetch merely because the
token was already high when it appeared.

Also extracted while building this: `.shelfPanel()`
(`Views/Shared/ShelfPanel.swift`), the rounded `secondarySystemBackground`
backdrop one shelf sits on, previously private to `ExploreTabView` and
now drawn by both screens.

**`shelfPanel(tinted:)` has exactly two treatments, and that's the
point.** Shelves that exist because of who the reader is — `For You`,
`Because You Read`, `More By` (`HomeShelf.isPersonal`) — sit on the
accent colour at 10% over the gray; everything else keeps the plain
gray. A colour per shelf kind would be a palette, which this app
deliberately doesn't have, and the accent is the one colour the system
already gives every control here. The wash goes *over*
`secondarySystemBackground` rather than replacing it, or the panel loses
its value in dark mode; it stays barely-there because the cards on top
are `systemBackground` and need a quiet backdrop.
