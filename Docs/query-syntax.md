# INSPIRE query syntax

Everything Explore and New need is expressible as a `q=` string, so both
tabs are just `PaperService.search` with a different query — no new
service methods.

| Purpose | Query |
| --- | --- |
| Primary category | `primarch hep-ph` |
| Category incl. cross-lists | `arxiv_eprints.categories:hep-ph` |
| A single day / a range | `de 2026-08-19`, `de > 2026-08-01` |
| Citation threshold | `topcite 1000+` (the `+` must be escaped — see `InspireHEPClient`) |
| Experiment | `collaboration:ATLAS` |
| Document type | `tc r` review, `tc l` lectures, `tc t` thesis, `tc c` conference |
| Papers citing a record | `refersto:recid:451647` |
| Citing **any** of a set | `refersto:recid:A or refersto:recid:B` — a true union |
| Citing **both** (co-citation) | `refersto:recid:A and refersto:recid:B` |
| A record's own references | `citedby:recid:451647` |
| Exclusion | `… and not recid:X` |
| Authors as a set | `(authors.recid:A or authors.recid:B) and de > …` |
| Subject keyword | `k "AdS/CFT correspondence"` — `keyword` and `keywords.value:` are the same thing |
| Keywords combined | `k "A" and k "B"`, `k "A" or k "B"` |

Combine with ` and `. Sorting is the `sort` parameter (`mostrecent` /
`mostcited`), not part of `q`. **The union is the load-bearing one for
recommendations: INSPIRE performs the join, so a whole reading profile
costs one request**, not one per seed.

- **The API returns no facets.** `aggregations` comes back empty even
  with `facet_name=search`, which the web UI uses. Explore's category
  and collaboration lists have to be a static table in the app; there's
  nothing to fetch them from.
- **`primarch` vs `arxiv_eprints.categories` is a real choice, not a
  synonym** — roughly 20% apart in hit count. New uses the
  cross-list-inclusive form: a hep-ph paper cross-listed to hep-th is
  something a hep-th reader wants, and arXiv's own daily listing shows
  cross-lists too. Explore's category browsing uses `primarch`, where
  the point is the character of the category itself. Worth keeping as
  two named queries on `ArxivCategory` rather than one flag.
- **A day is small**: on the order of a hundred records across all of
  INSPIRE, fewer per individual category. One day fits in a screen or
  two, which is what makes New's day-by-day grouping viable. arXiv
  publishes on weekdays only, so empty day sections have to be skipped
  rather than rendered.
- `tc`-style type codes are the working syntax; `doc_type:review`
  returns 0.
