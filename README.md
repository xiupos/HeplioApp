# heplio-ios

A search of [INSPIRE-HEP](https://inspirehep.net) for iPhone and iPad. It shows what INSPIRE finds: the papers a query finds, with the start of their abstracts, and each paper in detail. It keeps no papers: copy a paper's key, and add it to your library with [refdir-ios](https://github.com/xiupos/refdir-ios). Its behaviour is [heplio-gtk's SPEC.md](https://github.com/xiupos/heplio/blob/main/SPEC.md), with its examples in [cases.json](cases.json).

Heplio is not affiliated with INSPIRE.

## Usage

- Search in INSPIRE's [search syntax](https://help.inspirehep.net/knowledge-base/inspire-paper-search/),
  or by an arXiv number, DOI, texkey, or link, sorted by date, citations, or relevance
- See a paper's abstract, authors and their affiliations, journals, arXiv number, DOIs, and
  keywords; its citations, references, and each author open as searches
- Copy its key or its BibTeX; read its PDF from arXiv
- Save the queries you come back to, starting with the week's hep-th

## Building

Open `HeplioApp.swiftpm` in Swift Playgrounds on an iPad (iPadOS 26 or later) and run it. It has no dependencies.

## See also

- [heplio-gtk](https://github.com/xiupos/heplio): Heplio for GNOME, with the `heplio` command
- [refdir-ios](https://github.com/xiupos/refdir-ios): the library the keys go to

## License

[MIT](LICENSE)
