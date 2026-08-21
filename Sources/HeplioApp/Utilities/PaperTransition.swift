import SwiftUI

/// The namespace tying a tapped `PaperCardView` to the detail screen it
/// opens, for the system zoom transition — the same continuous
/// expand/collapse the App Store uses for an app card.
///
/// Carried in the environment for exactly the reason `paperOrigin` is:
/// the push is a plain `NavigationLink(value:)` deep inside a shared row
/// or card, and which stack's namespace it belongs to is context, not
/// something a row should have to be handed.
///
/// Set it on the `NavigationStack` itself, not on a view inside it —
/// pushed destinations inherit the stack's environment, not that of the
/// subview `.navigationDestination` happens to be attached to.
///
/// Optional because `Namespace.ID` can't be constructed: a screen with no
/// namespace installed (a preview, a stack that hasn't opted in) simply
/// gets the standard push instead.
extension EnvironmentValues {
    @Entry var paperTransitionNamespace: Namespace.ID?
}

/// A paper pushed by a card that zooms into it — the same
/// `PaperDetailView`, reached by a distinct navigation value.
///
/// It has to be distinct. A destination can't tell what pushed it, and
/// **a `.zoom` whose source id isn't registered does not fall back to a
/// push — the screen pops in from nothing** (seen on device). So the two
/// ways in need two values: a card pushes `ZoomedPaper`, everything else
/// pushes `Paper` and gets the ordinary slide.
struct ZoomedPaper: Hashable {
    let paper: Paper

    init(_ paper: Paper) {
        self.paper = paper
    }
}

extension View {
    /// Marks this view as the thing a paper's detail screen grows out of,
    /// and shrinks back into on the way out.
    ///
    /// **`PaperCardView` and `HeadlineView` use this, and only the whole
    /// card or headline.** Both are bounded blocks with an edge of their
    /// own — a rounded, elevated card, or a column of newsprint boxed in
    /// by rules — so growing one into a screen reads as opening the thing
    /// you touched. A `List` row isn't: it's full-width, chrome-less, and
    /// already carries a disclosure chevron promising a push, so it gets
    /// the plain push it promises.
    ///
    /// **Never attach it to a subview.** `.zoom` scales the source's
    /// rectangle up to the full destination and cross-fades; it does not
    /// pair elements the way the web's View Transitions API does.
    /// Anchored to the title alone (tried, on device) the title inflates
    /// to fill the screen, flies off, and the detail screen fades in from
    /// nothing.
    ///
    /// Inert for papers with no INSPIRE record — those rows link out to
    /// the web instead of pushing, so there's no destination to pair with,
    /// and they'd otherwise crowd the namespace with ids no push uses.
    func paperTransitionSource(_ paper: Paper) -> some View {
        modifier(PaperTransitionSource(paper: paper))
    }

    /// The receiving half, applied only to the `ZoomedPaper` destination.
    func paperZoomTransition(_ paper: Paper) -> some View {
        modifier(PaperZoomTransition(paper: paper))
    }
}

private struct PaperTransitionSource: ViewModifier {
    let paper: Paper
    @Environment(\.paperTransitionNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace, paper.hasInspireRecord {
            content.matchedTransitionSource(id: paper.id, in: namespace)
        } else {
            content
        }
    }
}

private struct PaperZoomTransition: ViewModifier {
    let paper: Paper
    @Environment(\.paperTransitionNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: paper.id, in: namespace))
        } else {
            content
        }
    }
}
