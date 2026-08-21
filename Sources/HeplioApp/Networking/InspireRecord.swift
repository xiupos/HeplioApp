import Foundation

/// INSPIRE's literature record wire format — `{ id, metadata: { ... } }`,
/// shared by search hits (`hits.hits[]`) and the detail endpoint — mapped
/// onto `Paper`. Kept out of the model so `Paper`'s own `Codable` stays
/// the synthesized, round-trippable one the cache stores.
struct InspireRecord: Decodable {
    let paper: Paper

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)
        // INSPIRE returns the record id as a numeric string (e.g. "3188089"), not a JSON number.
        let id: Int
        if let idString = try? container.decode(String.self, forKey: .id), let parsedID = Int(idString) {
            id = parsedID
        } else {
            id = try container.decode(Int.self, forKey: .id)
        }
        let metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata) ?? Metadata()
        let eprint = metadata.arxivEprints?.first
        let publicationInfo = metadata.publicationInfo?.first

        paper = Paper(
            id: id,
            title: metadata.titles?.first?.title ?? "Untitled",
            authors: metadata.authors?.map(Self.author(for:)) ?? [],
            abstract: metadata.abstracts?.first?.value,
            arxivID: eprint?.value,
            arxivCategories: eprint?.categories ?? [],
            doi: metadata.dois?.first?.value,
            journalTitle: publicationInfo?.journalTitle,
            journalVolume: publicationInfo?.journalVolume,
            pageStart: publicationInfo?.pageStart,
            year: publicationInfo?.year,
            collaborations: metadata.collaborations?.map(\.value) ?? [],
            citationCount: metadata.citationCount ?? 0,
            earliestDate: metadata.earliestDate,
            keywords: metadata.keywords.map { $0.compactMap(\.value) },
            figures: metadata.figures?.compactMap(Self.figure(for:)) ?? [],
            references: metadata.references?.compactMap(Self.referencePaper(for:)) ?? [],
            hasInspireRecord: true,
            referenceURL: nil
        )
    }

    private static func author(for field: AuthorField) -> Paper.Author {
        Paper.Author(
            fullName: field.fullName,
            affiliations: field.affiliations?.map(\.value) ?? [],
            recordID: field.record?.id
        )
    }

    /// Some entries — tables, mostly — are recorded as figures whose
    /// caption INSPIRE prefixes with `noimg:`, and the file behind them is
    /// a blank 300×300 placeholder rather than a real plot. Dropping them
    /// keeps empty cards out of the carousel.
    private static func figure(for field: FigureField) -> Paper.Figure? {
        guard !(field.caption ?? "").hasPrefix("noimg:") else { return nil }
        return Paper.Figure(url: field.url, caption: field.caption, label: field.label)
    }

    /// A single bibliography entry as a lightweight `Paper`. Entries
    /// without a matched record (older papers, software, web links) are
    /// kept, just marked so views link out externally instead of
    /// navigating to an in-app detail screen.
    private static func referencePaper(for entry: ReferenceEntry) -> Paper? {
        let detail = entry.reference
        let recordID = entry.recordID
        // `title` is the real bibliographic title when INSPIRE parsed one
        // out; `misc` is a catch-all that's sometimes the title but for
        // collaboration-authored citations is just a bare tag like "[CMS]"
        // — so `title` has to win when both are present.
        //
        // **A matched record survives even with no title at all**, falling
        // back to the journal citation the entry *is* identified by. Older
        // papers cite by journal line rather than by title, and INSPIRE
        // stores them that way. Dropping those left old papers with an
        // empty `references` array, which silently emptied both the
        // References carousel and `Recommender`'s `.sharedFoundations`
        // edge, since that walks out through exactly these record ids. It
        // read as "old papers have no related papers"; it was a decoding
        // gap.
        //
        // The stub label rarely reaches the screen anyway —
        // `PaperService.references(of:)` swaps every matched entry for its
        // full record — and `Recommender` only ever reads the id.
        let parsedTitle = detail?.title?.title ?? detail?.misc?.first ?? entry.rawRefs?.first?.value
        guard let title = parsedTitle
                ?? Self.citationLabel(for: detail)
                ?? (recordID != nil ? "Untitled" : nil) else {
            return nil
        }
        let hasAuthors = !(detail?.authors?.isEmpty ?? true)
        let hasDOI = !(detail?.dois?.isEmpty ?? true)
        let hasURL = !(detail?.urls?.isEmpty ?? true)
        // A handful of raw citations are just a stray "[hep-th]"-style tag
        // with nothing else to them — no title, no author, no matched
        // record, no DOI or URL. Nothing worth showing.
        if recordID == nil, !hasAuthors, !hasDOI, !hasURL,
           title.range(of: #"^\[[^\]]+\]\.?$"#, options: .regularExpression) != nil {
            return nil
        }
        return Paper(
            id: recordID ?? syntheticID(seed: "\(title)|\(detail?.dois?.first ?? "")"),
            title: title,
            authors: detail?.authors?.map(Self.author(for:)) ?? [],
            abstract: nil,
            arxivID: detail?.arxivEprint,
            arxivCategories: [],
            doi: detail?.dois?.first,
            journalTitle: detail?.publicationInfo?.journalTitle,
            journalVolume: detail?.publicationInfo?.journalVolume,
            pageStart: detail?.publicationInfo?.pageStart,
            year: detail?.publicationInfo?.year,
            collaborations: detail?.collaborations ?? [],
            citationCount: 0,
            earliestDate: nil,
            // A bibliography entry carries no keywords of its own;
            // `PaperService.references(of:)` swaps in the full record.
            keywords: nil,
            figures: [],
            references: [],
            hasInspireRecord: recordID != nil,
            referenceURL: detail?.urls?.first?.value
        )
    }

    /// How a citation names itself when it has no parsed title: the
    /// journal line ("Mod.Phys.Lett.A 4 2073"), or the arXiv id. Both are
    /// what a bibliography would print, so neither reads as a placeholder.
    private static func citationLabel(for detail: ReferenceEntry.ReferenceDetail?) -> String? {
        if let info = detail?.publicationInfo, let journal = info.journalTitle {
            return [journal, info.journalVolume, info.pageStart]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return detail?.arxivEprint.map { "arXiv:\($0)" }
    }

    /// A stable negative id for references INSPIRE couldn't match to a
    /// record — real INSPIRE ids are always positive, so this can't
    /// collide, and Identifiable/Hashable only need it to be unique.
    /// FNV-1a rather than `hashValue`, which is seeded per process and so
    /// wouldn't survive a trip through the cache.
    private static func syntheticID(seed: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return -Int(hash % UInt64(Int.max)) - 1
    }

    private enum RootKeys: String, CodingKey {
        case id
        case metadata
    }

    private struct Metadata: Decodable {
        var titles: [TitleField]?
        var authors: [AuthorField]?
        var abstracts: [ValueField]?
        var arxivEprints: [ArxivEprint]?
        var dois: [ValueField]?
        var publicationInfo: [PublicationInfo]?
        var collaborations: [ValueField]?
        var citationCount: Int?
        var earliestDate: String?
        var keywords: [KeywordField]?
        var figures: [FigureField]?
        var references: [ReferenceEntry]?

        enum CodingKeys: String, CodingKey {
            case titles, authors, abstracts
            case arxivEprints = "arxiv_eprints"
            case dois
            case publicationInfo = "publication_info"
            case collaborations
            case citationCount = "citation_count"
            case earliestDate = "earliest_date"
            case keywords
            case figures
            case references
        }

        init() {}
    }

    private struct TitleField: Decodable {
        let title: String
    }

    /// One subject keyword. `schema` distinguishes INSPIRE's own curated
    /// vocabulary from a publisher's author-supplied list, and there is a
    /// real difference: measured by year, INSPIRE-curated keywords cover
    /// 100% of hep-th papers up to about 2022 and 0% from 2024 on — the
    /// indexing runs a couple of years behind. Recent papers carry only
    /// the free-form author keywords, which are inconsistent
    /// ("holography" next to "Gauge-Gravity Correspondence") but real.
    /// Both are taken; `value` is the only field either kind needs.
    private struct KeywordField: Decodable {
        let value: String?
        let schema: String?
    }

    private struct ValueField: Decodable {
        let value: String
    }

    private struct AuthorField: Decodable {
        let fullName: String
        let affiliations: [ValueField]?
        let record: RecordRef?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case affiliations
            case record
        }
    }

    /// INSPIRE links records to each other by API URL rather than by bare
    /// id, so the id has to come off the end of the path.
    private struct RecordRef: Decodable {
        let ref: String

        var id: Int? { Int(ref.split(separator: "/").last ?? "") }

        enum CodingKeys: String, CodingKey { case ref = "$ref" }
    }

    private struct FigureField: Decodable {
        let url: String
        let caption: String?
        let label: String?
    }

    private struct ArxivEprint: Decodable {
        let value: String
        let categories: [String]?
    }

    private struct PublicationInfo: Decodable {
        let journalTitle: String?
        let journalVolume: String?
        let pageStart: String?
        let year: Int?

        enum CodingKeys: String, CodingKey {
            case journalTitle = "journal_title"
            case journalVolume = "journal_volume"
            case pageStart = "page_start"
            case year
        }
    }

    private struct ReferenceEntry: Decodable {
        let record: RecordRef?
        let reference: ReferenceDetail?
        let rawRefs: [ValueField]?

        /// The INSPIRE record this reference resolves to, if any.
        var recordID: Int? { record?.id }

        enum CodingKeys: String, CodingKey {
            case record, reference
            case rawRefs = "raw_refs"
        }

        struct ReferenceDetail: Decodable {
            let misc: [String]?
            let title: TitleField?
            let authors: [AuthorField]?
            let collaborations: [String]?
            let arxivEprint: String?
            let publicationInfo: PublicationInfo?
            let dois: [String]?
            let urls: [ValueField]?

            enum CodingKeys: String, CodingKey {
                case misc, title, authors, collaborations, dois, urls
                case arxivEprint = "arxiv_eprint"
                case publicationInfo = "publication_info"
            }
        }
    }
}
