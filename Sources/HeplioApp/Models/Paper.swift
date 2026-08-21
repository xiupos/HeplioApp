import Foundation

/// A literature record, as the app uses it. A plain value type with
/// synthesized `Codable`, so it round-trips through `ResponseCache` —
/// INSPIRE's own `{ id, metadata: {...} }` wire format is decoded
/// separately by `InspireRecord`.
struct Paper: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let authors: [Author]
    let abstract: String?
    let arxivID: String?
    let arxivCategories: [String]
    let doi: String?
    let journalTitle: String?
    let journalVolume: String?
    let pageStart: String?
    let year: Int?
    let collaborations: [String]
    let citationCount: Int
    let earliestDate: String?
    /// Plots and diagrams INSPIRE extracted from the paper and hosts
    /// itself. Empty for records it has no fulltext for.
    let figures: [Figure]
    /// The record's bibliography, as INSPIRE embeds it: lightweight
    /// entries, without abstracts and often with mangled titles. Views
    /// don't render these directly — `PaperService.references(of:)` swaps
    /// each matched entry for its real record first.
    let references: [Paper]
    /// False for references INSPIRE couldn't match to a record of its own
    /// (older papers, software citations, web links) — these have no valid
    /// `id`/`inspireURL` and can't be fetched or navigated to internally.
    let hasInspireRecord: Bool
    /// Fallback link (e.g. a plain URL cited in the reference) for entries
    /// without `doi` or an INSPIRE record — the closest thing to "send them
    /// somewhere appropriate" when there's nothing to show in-app.
    let referenceURL: String?

    struct Author: Codable, Hashable, Identifiable {
        var id: String { recordID.map(String.init) ?? fullName }
        let fullName: String
        let affiliations: [String]
        /// INSPIRE's own author record, where it has attached this
        /// signature to a person. Present on essentially every author of
        /// a curated record — including all 2,932 of a collaboration
        /// paper's — and it's what tells two physicists publishing under
        /// the same name apart.
        let recordID: Int?
    }

    /// One extracted figure. INSPIRE serves these straight from
    /// `inspirehep.net/files/…` as PNGs, no authentication.
    struct Figure: Codable, Hashable, Identifiable {
        var id: String { url }
        let url: String
        /// The paper's own caption — full LaTeX, often several sentences.
        let caption: String?
        /// How the paper refers to it, e.g. "FIG. 3".
        let label: String?

        var imageURL: URL? { URL(string: url) }
    }
}

extension Paper.Author {
    /// "Weiglein, Georg (DESY)" for the detail header. INSPIRE already
    /// publishes affiliations in short form — "DESY", "Madrid, IFT",
    /// "U. Heidelberg, ITP" — so this takes the first one as given rather
    /// than abbreviating further and losing the institute. Authors with
    /// several affiliations show only the first.
    var nameWithAffiliation: String {
        guard let affiliation = affiliations.first else { return fullName }
        return "\(fullName) (\(affiliation))"
    }

    /// The author's page on inspirehep.net. Only signatures INSPIRE has
    /// attached to an author record have one — the rest are a name this
    /// app searches for, not a person INSPIRE knows about.
    var inspireURL: URL? {
        recordID.flatMap { URL(string: "https://inspirehep.net/authors/\($0)") }
    }

    /// Finds this author's papers. By INSPIRE's disambiguated author
    /// record where there is one — verified against the API, that's a
    /// narrower and more accurate set than a name match (72 papers vs 82
    /// for one test author, the difference being other people's work).
    /// Signatures INSPIRE hasn't attached to a record fall back to the
    /// name, which is fuzzy but better than refusing to look.
    var papersQuery: String {
        recordID.map { "authors.recid:\($0)" } ?? "a \(fullName)"
    }
}

extension Paper {
    /// A row-sized copy: everything `PaperRowView`/`PaperCardView` render
    /// and nothing else. What gets stored in the library and history —
    /// the detail screen refetches the full record, so the parts left out
    /// here are never missed, and they're the expensive parts. A
    /// collaboration paper carries thousands of authors and a bibliography
    /// running to megabytes; trimmed, a saved paper is a couple of KB,
    /// which matters once this syncs over iCloud.
    var summary: Paper {
        Paper(
            id: id,
            title: title,
            // One past what a row shows, so "et al." still knows there
            // were more.
            authors: Array(authors.prefix(4)),
            abstract: abstract,
            arxivID: arxivID,
            arxivCategories: arxivCategories,
            doi: doi,
            journalTitle: journalTitle,
            journalVolume: journalVolume,
            pageStart: pageStart,
            year: year,
            collaborations: collaborations,
            citationCount: citationCount,
            earliestDate: earliestDate,
            // Figures are the detail screen's, and it always refetches.
            figures: [],
            references: [],
            hasInspireRecord: hasInspireRecord,
            referenceURL: referenceURL
        )
    }

    /// The one plot a headline shows. INSPIRE lists figures in the order
    /// they appear in the paper, so the first is usually apparatus or a
    /// Feynman diagram and the last is usually the result — which is the
    /// one worth putting above a headline. (The same choice the web
    /// version of this feed makes; `PaperDetailView` still shows all of
    /// them.)
    var headlineFigure: Figure? { figures.last }

    var inspireURL: URL? {
        guard hasInspireRecord else { return nil }
        return URL(string: "https://inspirehep.net/literature/\(id)")
    }

    var pdfURL: URL? {
        guard let arxivID else { return nil }
        return URL(string: "https://arxiv.org/pdf/\(arxivID)")
    }

    /// Where to send someone who taps a reference INSPIRE has no record
    /// for: its DOI if it has one, else whatever URL the citation itself
    /// pointed to.
    var externalLinkURL: URL? {
        if let doi, !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        if let referenceURL { return URL(string: referenceURL) }
        return nil
    }

    /// e.g. "Phys.Lett.B 716 1" — journal title, volume, and start page.
    var journalCitation: String? {
        guard let journalTitle, !journalTitle.isEmpty else { return nil }
        var parts = [journalTitle]
        if let journalVolume, !journalVolume.isEmpty { parts.append(journalVolume) }
        if let pageStart, !pageStart.isEmpty { parts.append(pageStart) }
        return parts.joined(separator: " ")
    }

    /// Up to the first 3 author names, semicolon-separated (each name is
    /// itself "Last, First", so a comma can't also separate people without
    /// ambiguity), with an "et al." suffix if there are more. Empty when
    /// there's nothing to credit at all, which some unmatched references
    /// (a bare URL, say) genuinely have — callers skip the line then.
    var authorsSummaryLine: String {
        guard !authors.isEmpty else { return collaborations.first ?? "" }
        let names = authors.prefix(3).map(\.fullName).joined(separator: "; ")
        return authors.count > 3 ? "\(names); et al." : names
    }

    /// A News-style "kicker" label above the headline: the collaboration,
    /// primary arXiv category, or journal — whichever is most identifying.
    var kicker: String? {
        if let collaboration = collaborations.first { return collaboration }
        if let category = arxivCategories.first {
            // Records carry categories beyond the ones Explore browses,
            // so an unknown one shows as-is rather than not at all.
            return ArxivCategory(rawValue: category)?.displayName ?? category
        }
        if let journalTitle, !journalTitle.isEmpty { return journalTitle }
        return nil
    }

    /// `earliestDate` formatted at whatever precision INSPIRE provided
    /// (year, year-month, or full date), falling back to the bare year.
    var formattedDate: String? {
        guard let earliestDate, !earliestDate.isEmpty else {
            return year.map(String.init)
        }
        // The component count decides the precision before anything is
        // parsed: `yyyy-MM-dd` will happily read "2026-12" as the first of
        // December, which would invent a day INSPIRE never claimed.
        switch earliestDate.split(separator: "-").count {
        case 3:
            if let date = DateFormatter.inspireDay.date(from: earliestDate) {
                return date.formatted(.dateTime.year().month(.abbreviated).day())
            }
        case 2:
            if let date = DateFormatter.inspireMonth.date(from: earliestDate) {
                return date.formatted(.dateTime.year().month(.abbreviated))
            }
        default:
            break
        }
        return earliestDate
    }
}
