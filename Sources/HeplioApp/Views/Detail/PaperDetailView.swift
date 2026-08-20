import SwiftUI
import SwiftData
import QuickLook

struct PaperDetailView: View {
    let paper: Paper

    @Environment(\.modelContext) private var modelContext
    @Environment(\.paperOrigin) private var paperOrigin
    /// Non-nil only when this screen was reached by pushing inside a modal
    /// sheet (currently History) — lets the reader pop back out to the
    /// same paper on the Library tab's full-width stack.
    @Environment(\.openInLibrary) private var openInLibrary

    /// Empty unless this paper is bookmarked — a query rather than a
    /// one-off fetch so the button follows along if the bookmark changes
    /// elsewhere (or, later, on another device).
    @Query private var savedMatches: [SavedPaper]

    init(paper: Paper) {
        self.paper = paper
        let id = paper.id
        _savedMatches = Query(filter: #Predicate<SavedPaper> { $0.paperID == id })
    }

    private var isSaved: Bool { !savedMatches.isEmpty }

    /// Three independent loads, each with its own state: the screen waits
    /// on the record itself, while the two carousels below show their own
    /// spinners until their pages arrive. They overlap — `PaperService`
    /// de-duplicates the record fetch `references` also needs — so nothing
    /// waits on anything it doesn't actually need.
    @State private var detail: LoadState<Paper> = .loading
    @State private var references: LoadState<[Paper]> = .loading
    @State private var citations: LoadState<[Paper]> = .loading

    /// One Quick Look presentation shared by the PDF button and the
    /// figure strip: `items` is what a swipe can page through (a lone PDF,
    /// or every figure in order), `previewURL` is what's on screen.
    @State private var previewURL: URL?
    @State private var previewItems: [URL] = []

    @State private var isDownloadingPDF = false
    @State private var pdfDownloadFailed = false
    @State private var preparingFigureID: Paper.Figure.ID?
    @State private var figureDownloadFailed = false

    /// The row/card that got us here already carries most of the record;
    /// the fetched one fills in the abstract and the bibliography.
    private var displayedPaper: Paper { detail.value ?? paper }

    var body: some View {
        Group {
            switch detail {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                // This branch replaces the ScrollView, so there's nothing
                // left to pull on — hence an explicit retry.
                ContentUnavailableView {
                    Label("Couldn't Load Paper", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task { await refreshAll() }
                    }
                }
            case .loaded:
                content
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let openInLibrary {
                // Separate from the save/share island below — this is a
                // navigation action (leave the sheet), not something to do
                // with the paper itself.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openInLibrary(displayedPaper)
                    } label: {
                        Label("Open in Library", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            // Grouped so they read as one Music/News-style toolbar island.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if displayedPaper.hasInspireRecord {
                    Button {
                        modelContext.toggleSaved(displayedPaper)
                    } label: {
                        Label(
                            isSaved ? "Remove from Library" : "Save to Library",
                            systemImage: isSaved ? "bookmark.fill" : "bookmark"
                        )
                    }
                }
                if let inspireURL = displayedPaper.inspireURL {
                    ShareLink(item: inspireURL, subject: Text(displayedPaper.title))
                }
            }
        }
        .quickLookPreview($previewURL, in: previewItems)
        .alert("Couldn't Open PDF", isPresented: $pdfDownloadFailed) {
            Button("OK", role: .cancel) {}
        }
        .alert("Couldn't Open Figure", isPresented: $figureDownloadFailed) {
            Button("OK", role: .cancel) {}
        }
        .task(id: paper.id) { await loadRecord() }
        .task(id: paper.id) { await loadReferences() }
        .task(id: paper.id) { await loadCitations() }
    }

    // MARK: - Loading

    private func loadRecord(refresh: Bool = false) async {
        detail = await .load { try await PaperService.shared.details(id: paper.id, refresh: refresh) }
        // Recorded from the fetched record, not the row that got us here:
        // a reference card's stub title is often mangled, and History
        // should show what the reader actually read.
        if let loaded = detail.value {
            modelContext.recordView(of: loaded, fromSearch: paperOrigin.isSearch)
            if let query = paperOrigin.searchQuery {
                modelContext.recordSearch(query)
            }
        }
    }

    private func loadReferences(refresh: Bool = false) async {
        references = await .load {
            try await PaperService.shared.references(of: paper.id, refresh: refresh)
        }
    }

    private func loadCitations(refresh: Bool = false) async {
        citations = await .load {
            try await PaperService.shared.citations(of: paper.id, refresh: refresh)
        }
    }

    /// Pull-to-refresh. The three loads run concurrently, as on first
    /// open, and the spinner stays until the last one lands. The carousels
    /// aren't put back into `.loading` first — their existing cards are
    /// better company for the refresh control than two empty spinners.
    private func refreshAll() async {
        async let record: Void = loadRecord(refresh: true)
        async let refs: Void = loadReferences(refresh: true)
        async let cites: Void = loadCitations(refresh: true)
        _ = await (record, refs, cites)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                paperBlock
                relatedContent
            }
        }
        .refreshable { await refreshAll() }
        // Full-bleed gray backdrop behind the related-content panel: to
        // the tab bar at the bottom, and out to the screen edges
        // horizontally, where an iPad's sidebar otherwise leaves it
        // stopping short at its own column. Every edge but the top —
        // ignoring that one lets the gray show through the translucent
        // nav bar above the (white) header.
        .background(
            Color(.secondarySystemBackground)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        )
    }

    /// The white upper half: everything about the paper itself, above the
    /// gray related-content panel. Padding is applied per group rather
    /// than to the whole block, because the figure strip in the middle
    /// runs to both screen edges and manages its own insets.
    private var paperBlock: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                PaperHeaderView(paper: displayedPaper)
                actions
            }
            .padding(.horizontal)

            // Between the title block and the abstract, where the App
            // Store puts screenshots.
            if !displayedPaper.figures.isEmpty {
                FigureCarouselView(
                    figures: displayedPaper.figures,
                    preparingID: preparingFigureID
                ) { figure in
                    Task { await previewFigure(figure) }
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                if let abstract = displayedPaper.abstract, !abstract.isEmpty {
                    abstractSection
                }
                Divider()
                metadataFooter
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .padding(.bottom, 16)
        .background(alignment: .top) {
            // Extends well past the top of the content so a strong
            // pull-to-refresh overscroll still reveals white, not the gray
            // backdrop behind the related-content panel.
            Color(.systemBackground)
                .frame(height: 1000)
                .offset(y: -1000)
        }
        .background(Color(.systemBackground))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if displayedPaper.pdfURL != nil {
                Button {
                    Task { await downloadAndPreviewPDF() }
                } label: {
                    if isDownloadingPDF {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("View PDF", systemImage: "text.document")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloadingPDF)
            }

            if let inspireURL = displayedPaper.inspireURL {
                Link(destination: inspireURL) {
                    Label("INSPIRE-HEP", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    /// Previewed in-app via Quick Look rather than opened in the browser.
    private func downloadAndPreviewPDF() async {
        guard let pdfURL = displayedPaper.pdfURL else { return }
        isDownloadingPDF = true
        defer { isDownloadingPDF = false }
        guard let file = try? await TemporaryDownload.file(
            from: pdfURL,
            named: "paper-\(displayedPaper.id).pdf"
        ) else {
            pdfDownloadFailed = true
            return
        }
        previewItems = [file]
        previewURL = file
    }

    /// Quick Look pages between items with a swipe — the App Store's
    /// screenshot viewer behaviour — but only over real files it's handed
    /// up front, so tapping one figure fetches them all. They're small
    /// (tens of KB each) and kept on disk, so this is a wait once per
    /// paper rather than once per figure.
    private func previewFigure(_ figure: Paper.Figure) async {
        preparingFigureID = figure.id
        defer { preparingFigureID = nil }
        let files = await TemporaryDownload.files(displayedPaper.figures.compactMap(\.downloadItem))
        guard let selected = figure.previewFileURL, files.contains(selected) else {
            figureDownloadFailed = true
            return
        }
        previewItems = files
        previewURL = selected
    }

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abstract")
                .font(.headline)
            MathTextView(text: displayedPaper.abstract ?? "", fontTextStyle: .body)
        }
    }

    /// Muted footer, like Apple Music's album/song credits treatment.
    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let journalCitation = displayedPaper.journalCitation {
                Text(journalCitation)
            }
            if let arxivID = displayedPaper.arxivID {
                Text("arXiv:\(arxivID)")
            }
            if let doi = displayedPaper.doi {
                Text("DOI: \(doi)")
            }
            if displayedPaper.hasInspireRecord {
                Text("INSPIRE-HEP record #\(displayedPaper.id)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Related content (References / Cited By / Related carousels)

    private var relatedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            carousel(kind: .references, state: references)
            carousel(kind: .citedBy, state: citations)

            PaperCarouselView(
                title: RelatedPapersDestination.Kind.related.title,
                destination: destination(for: .related),
                state: .loaded([])
            ) {
                ContentUnavailableView("No Related Papers Yet", systemImage: "sparkles")
                    .frame(width: 260, height: 148)
                    .scaleEffect(0.8)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
            }
        }
        .padding(.bottom)
    }

    /// Hidden entirely once it's known there's nothing to show — a paper
    /// with no references, or one nothing has cited yet, shouldn't leave
    /// an empty heading behind.
    @ViewBuilder
    private func carousel(kind: RelatedPapersDestination.Kind, state: LoadState<[Paper]>) -> some View {
        if state.isLoading || state.value?.isEmpty == false {
            PaperCarouselView(
                title: kind.title,
                destination: destination(for: kind),
                state: state,
                numberFor: kind.numberFor
            )
        }
    }

    private func destination(for kind: RelatedPapersDestination.Kind) -> RelatedPapersDestination {
        RelatedPapersDestination(kind: kind, sourcePaper: displayedPaper)
    }
}

#Preview {
    NavigationStack {
        PaperDetailView(paper: .preview)
    }
    .modelContainer(for: LibraryStore.models, inMemory: true)
}
