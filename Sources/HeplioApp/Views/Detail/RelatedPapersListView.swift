import SwiftUI

/// The search-results-style screen behind each carousel's "See All" —
/// same `PapersListView` content (and pagination) as `SearchTabView`, over
/// whichever page source the destination describes.
struct RelatedPapersListView: View {
    let destination: RelatedPapersDestination

    @State private var pager: PaperPager

    init(destination: RelatedPapersDestination) {
        self.destination = destination
        _pager = State(wrappedValue: destination.makePager())
    }

    var body: some View {
        List {
            PapersListView(
                pager: pager,
                numberFor: destination.kind.numberFor,
                itemNoun: destination.kind.itemNoun
            ) {
                if destination.kind == .related {
                    ContentUnavailableView(
                        "No Related Papers",
                        systemImage: "sparkles",
                        description: Text("INSPIRE hasn't matched enough of this paper's own references to build a list.")
                    )
                } else {
                    ContentUnavailableView("No Results", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .pagedPapersList(pager)
        .navigationTitle(destination.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        // The one paged screen with a fixed source — the destination
        // decided what it lists — so this loads once and never reloads.
        .task { await pager.loadInitialIfNeeded() }
    }
}

#Preview {
    NavigationStack {
        RelatedPapersListView(destination: RelatedPapersDestination(kind: .references, sourcePaper: .preview))
    }
    .modelContainer(for: LibraryStore.models, inMemory: true)
}
