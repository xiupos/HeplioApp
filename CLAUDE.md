# Implementation Notes

Heplio for iOS and iPadOS: a search of INSPIRE-HEP. What the code does not say by itself: the
reasons behind decisions, pitfalls, and what only the iPad can check.

It implements heplio-gtk's `SPEC.md` (checked out at `~/Projects/heplio-gtk`), and its code,
`src/lib.rs`, is the rule where the spec says nothing. `cases.json` here is a copy of its
`tests/cases.json`: copy it again when it changes there. A change of behaviour goes into heplio-gtk
first. The app does what heplio-gtk's app does, in the platform's way, as refdir-ios
(`~/Projects/refdir-ios`) does refdir-gtk's: its layout, its code, and these notes follow
refdir-ios's. heplio-gtk's `CLAUDE.md` has the reasons that do not depend on the platform.

**Keep it small enough to read.** Four source files, no subfolders. It keeps no papers: no
library, tags, notes, or markup, which are refdir's. Nothing is cached but a launch's PDFs.

## Environment

- Swift Playgrounds on an iPad; there is no Mac and no Xcode. The project is written on Linux and
  synced to the iPad with Syncthing.
- `Package.swift` is as Playgrounds writes it: change it only as its app settings would, except
  for `additionalInfoPlistContentFilePath: "Info.plist"`. One target, `AppModule`, with
  `path: "."`, so every `.swift` file in the project is compiled. No packages, no extensions.
- `Info.plist` holds `ITSAppUsesNonExemptEncryption` = `false`: the app uses only the system's
  HTTPS, which is exempt. Playgrounds may drop the line of `Package.swift` that merges it: check
  it before uploading a build.
- Fixed: the name Heplio, bundle ID `net.xiupos.heplio` and the team ID (the App Store's record,
  from the first heplio-ios, whose builds went to 6), the AppIcon (heplio-gtk's icon, full-bleed
  on its dark ground; for a dark home screen, on none, its tracks a step lighter; for a tinted
  one, in greys on none), made from its SVG with `rsvg-convert` and ImageMagick, the orange
  accent colour, iOS 26, Swift 5 language mode. UI text is in English.
- Syncthing may leave `*.sync-conflict-*` copies of files. In `Sources/` they cause "invalid
  redeclaration" errors: delete them first.

## Layout

| File | Contents |
|---|---|
| `Sources/Core.swift` | Foundation only, and everything in the spec: queries and links, requests, records, short names, counts, plain text, saved queries. Has the tests |
| `Sources/Fetch.swift` | The network: INSPIRE and arXiv |
| `Sources/App.swift` | `@main`, `Store` (the saved queries, the sort, the list and its pages, copying, PDFs), the places, the list |
| `Sources/Paper.swift` | `PaperPage`: one paper |
| `cases.json` | heplio-gtk's examples |

## Testing

`Core.swift` builds on Linux (Swift 6.4 here). Its tests, at the end of the file under
`#if os(Linux)`, run every section of `cases.json` as heplio-gtk's `tests/cases.rs` does.

```bash
swiftc -parse-as-library Sources/Core.swift -o /tmp/heplio-ios-test && /tmp/heplio-ios-test
/tmp/heplio-ios-test ~/Projects/heplio-gtk/tests/cases.json   # is the copy current?
swiftc -parse-as-library -typecheck Sources/Core.swift Sources/Fetch.swift
swiftc -frontend -parse Sources/App.swift Sources/Paper.swift   # syntax only
```

Everything that imports SwiftUI needs the iPad.

## Core

- **INSPIRE's JSON** is read with `JSONSerialization`, not `Codable`: a field may be a string or a
  number (`publication_info`'s), and a hit INSPIRE gives oddly is left out alone (`Record(hit:)`
  is failable). Lists ask for `first_author` and `author_count`, not `authors`: a collaboration's
  are megabytes. The page asks again for its one paper, with everything it shows.
- **Plain text** is refdir-ios's converter (`TeX`), copied, with INSPIRE's HTML undone first
  (`untagged`, `entities`): `<sup>` and `<sub>` become scripts. It reads `%`, `&`, and `#` as
  text already, and an odd `$` as a dollar. `\bar` is an overline (U+0305), as heplio-gtk's
  techxt makes it; refdir-ios's is a macron.
- **The sort is sent always**, as heplio-gtk sends it: INSPIRE takes an unknown one silently.

## UI

- **Three columns**: a `NavigationSplitView` of the places (INSPIRE, the saved queries), the
  list, and the paper. An iPhone shows one at a time, with no code of ours.
- **One list.** A paper's citations, references, and authors are queries shown in the list, with
  the query in the search field (`Store.open`), and the list's column shown where only one fits;
  the paper's page stays (`Store.paper`) until another is chosen.
- **The place follows the query shown** (`Store.show`, `saved`'s `didSet`): a saved one's, else
  INSPIRE. Choosing a saved query shows it; choosing INSPIRE leaves the search shown, unless
  that is a saved query, which it leaves for an empty one. Setting `place` inside its own
  `didSet` does not call it again, which is what keeps this from going round.
- **The sort** is the query shown's: showing a query sets it, and choosing another searches the
  query again. It is kept in `UserDefaults`, as the order of the next search.
- **Searches are numbered** (`Store.searchNumber`): a page answering a search that another has replaced
  is dropped. The next page is asked for when the last row appears, once at a time; one that
  fails says why, and the list keeps what it has. A paper INSPIRE gives again on a later page is
  not listed twice: the list's rows are identified by recid.
- **Rows are made off the main thread** (`Paper`): their TeX made plain once, the abstract's
  first 400 characters only, enough for two lines.
- **Saved queries** are `UserDefaults`' (`queries`, `[[q, sort]]`): there is no folder, and none
  is wanted for this alone. At first, the week's hep-th (`firstSaved`). The star saves or removes
  the query shown; a saved query's long press or a swipe to the left removes it.
- **Copying.** Copy Key and Copy BibTeX are a long press on a row, and buttons on the paper's
  page, which say "Copied". BibTeX is INSPIRE's, asked for when copied.
- **PDFs** are downloaded from arXiv into a launch's temporary folder (`Store.pdfs`, emptied at
  launch), then shown with Quick Look (`quickLookPreview`: there is no markup to save, which
  refdir-ios's `PDFReader` is for). One already there shows at once. A download is shown only if
  it is still the paper asked for last (`downloading`).

## Not verified

What only the iPad can check:

- That it builds, and every view: the search field and its submit, the sort menu, the star,
  paging at the end of the list, the paper's page, opening citations and authors on an iPhone
  (back to the list, the page popped), copying, Quick Look
- That Playgrounds builds the dark and tinted icons (`appearances` in the AppIcon's
  `Contents.json`): if not, the light one shows in every mode
