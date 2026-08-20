import SwiftUI

extension View {
    /// Every push a list of papers can lead to: the paper, a carousel's
    /// "See All" list, a paper's authors, one author's papers, and an
    /// Explore shelf entry.
    ///
    /// All of them are registered here, on the root of each tab's own
    /// `NavigationStack`, rather than on the screens that link to them —
    /// a `navigationDestination` declared on an already-pushed view only
    /// exists while that view does, which shows up as a push that grows
    /// the back stack without changing what's on screen.
    func paperNavigationDestinations() -> some View {
        navigationDestination(for: Paper.self) { paper in
            PaperDetailView(paper: paper)
        }
        // The same screen, reached from a carousel card, which it grows
        // out of. Two values rather than one because the zoom can't be
        // applied conditionally from in here — see `ZoomedPaper`.
        .navigationDestination(for: ZoomedPaper.self) { zoomed in
            PaperDetailView(paper: zoomed.paper)
                .paperZoomTransition(zoomed.paper)
        }
        .navigationDestination(for: RelatedPapersDestination.self) { destination in
            RelatedPapersListView(destination: destination)
        }
        .navigationDestination(for: AuthorListDestination.self) { destination in
            AuthorListView(destination: destination)
        }
        .navigationDestination(for: Paper.Author.self) { author in
            AuthorPapersView(author: author)
        }
        // Registered for every tab, not just Explore: New will push
        // topics too, and a paper's category kicker is the obvious next
        // place to link one from.
        .navigationDestination(for: BrowseTopic.self) { topic in
            BrowseListView(topic: topic)
        }
    }
}
