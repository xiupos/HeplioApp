import Foundation

/// The arXiv categories INSPIRE carries, as a type rather than a bare
/// string. Two things need naming here that a `String` can't hold: what
/// a category is called in words, and the fact that "papers in hep-th"
/// means one thing when browsing and another in a daily feed.
///
/// The list is static because it has to be: INSPIRE's search API returns
/// no facets (`aggregations` comes back empty even with the
/// `facet_name=search` its own web UI sends), so there is nothing to
/// fetch a category list *from*.
enum ArxivCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    // HEP proper, in the order a physicist would name them.
    case hepPh = "hep-ph"
    case hepTh = "hep-th"
    case hepEx = "hep-ex"
    case hepLat = "hep-lat"
    // Then the adjacent fields INSPIRE also indexes.
    case grQc = "gr-qc"
    case nuclTh = "nucl-th"
    case nuclEx = "nucl-ex"
    case astroPhCO = "astro-ph.CO"
    case astroPhHE = "astro-ph.HE"
    case physicsInsDet = "physics.ins-det"
    case quantPh = "quant-ph"
    case mathPh = "math-ph"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hepPh: return "Phenomenology"
        case .hepTh: return "Theory"
        case .hepEx: return "Experiment"
        case .hepLat: return "Lattice"
        case .grQc: return "Gravitation"
        case .nuclTh: return "Nuclear Theory"
        case .nuclEx: return "Nuclear Experiment"
        case .astroPhCO: return "Cosmology"
        case .astroPhHE: return "High Energy Astrophysics"
        case .physicsInsDet: return "Instrumentation"
        case .quantPh: return "Quantum Physics"
        case .mathPh: return "Mathematical Physics"
        }
    }

    /// Papers whose *primary* category is this one — what Explore browses.
    /// The point of a category shelf is the character of the field itself,
    /// which cross-listed papers blur.
    var browseQuery: String { "primarch \(rawValue)" }

    /// Papers filed here *or* cross-listed here — what a daily feed shows.
    /// A hep-ph paper cross-listed to hep-th is something a hep-th reader
    /// wants, and arXiv's own daily listing carries cross-lists too.
    ///
    /// Measured against the API: this is about 20% wider than
    /// `browseQuery` (hep-ph, 175,395 vs 144,214), so the two are a real
    /// choice and not synonyms.
    var feedQuery: String { "arxiv_eprints.categories:\(rawValue)" }
}
