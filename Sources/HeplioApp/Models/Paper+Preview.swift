/// A real record (the ATLAS Higgs discovery paper) for `#Preview` blocks
/// to draw, so a canvas shows the LaTeX, the long author list and the
/// citation count a row actually has to cope with.
///
/// **Deliberately not behind `#if DEBUG`, and putting it back breaks the
/// archive.** `#Preview` blocks are compiled into a release build too, so
/// a fixture that exists only in debug fails every view that references
/// it — the App Store Connect upload came back with a dozen "type 'Paper'
/// has no member 'preview'" errors from exactly that. Guarding each
/// `#Preview` instead would work, but it's a rule every new view has to
/// remember; one shipped struct is cheaper.
extension Paper {
    static let preview = Paper(
        id: 1124337,
        title: "Observation of a new particle in the search for the Standard Model Higgs boson with the ATLAS detector at the LHC",
        authors: [Author(fullName: "Aad, Georges", affiliations: ["CERN"], recordID: 1066085)],
        abstract: "A search for the Standard Model Higgs boson in proton–proton collisions with the ATLAS detector at the LHC.",
        arxivID: "1207.7214",
        arxivCategories: ["hep-ex"],
        doi: "10.1016/j.physletb.2012.08.020",
        journalTitle: "Phys.Lett.B",
        journalVolume: "716",
        pageStart: "1",
        year: 2012,
        collaborations: ["ATLAS"],
        citationCount: 17601,
        earliestDate: "2012-07",
        keywords: ["Higgs particle: hadroproduction", "CERN LHC Coll", "experimental results"],
        figures: [],
        references: [],
        hasInspireRecord: true,
        referenceURL: nil
    )
}
