# HeplioApp

An unofficial [INSPIRE-HEP](https://inspirehep.net) client for iPhone and iPad.

Everything it lists is the answer to an INSPIRE query: a search, an author's papers, a paper's references or citations. Queries and papers you keep are saved as JSON files in a folder you choose, which you can sync between devices.

Heplio is not affiliated with INSPIRE.

## Building

Open `HeplioApp.swiftpm` in Swift Playgrounds on an iPad (iPadOS 26 or later) and run it. It has no dependencies. A build is also on [TestFlight](https://testflight.apple.com/join/GtK8NEWV).

## Using

Search INSPIRE in the Search tab with INSPIRE's [search syntax](https://help.inspirehep.net/knowledge-base/inspire-paper-search/), for example `a Juan.M.Maldacena.1`, `t black hole and topcite 100+`, or `refersto:recid:451647`. Press Return to search.

- **A paper's page** shows its details and figures, links to its authors, references, and citations, to arXiv and the DOI, and copies its BibTeX.
- **Save** a paper with the star, or any list's query with the bookmark. Papers go to the Library tab; saved queries are in the Search tab.
- **Search** has two scopes, INSPIRE and Library, as Music has. In Library it finds among the saved papers as you type, by title, author, or tag, and lists the tags by namespace before you type.
- **Get PDF** downloads a paper's PDF from arXiv to the library. Papers with a PDF show its first page as their cover.
- **The library** is a folder (Settings) laid out as a [refdir](https://github.com/xiupos/refdir) library, so other refdir apps can open it: one folder per paper, with its `entry.json` and its PDF, and the saved queries in `.heplio/queries.json`. Keep it in iCloud Drive, or a folder another app syncs. It is read again when you come back to the app.

With a keyboard: ⌘, opens Settings, and ⌘S saves the paper shown.

## See also

- [heplio-gtk](https://github.com/xiupos/heplio-gtk): Heplio for GNOME, whose `spec/SPEC.md` describes the behaviour the apps share

## License

[MIT](LICENSE).
