import SwiftUI

extension View {
    /// The app's one card material: a `systemBackground` fill, a hairline
    /// `separator` border, and a shadow soft enough to lift the card off
    /// the `secondarySystemBackground` panel behind it without announcing
    /// itself. System semantic colors only — no palette.
    ///
    /// One modifier rather than the same five lines at each call site,
    /// because "the carousel and the grids read as one screen made of one
    /// thing" is a stated goal (see CLAUDE.md, Explore) and three
    /// hand-kept copies is how that quietly stops being true. Used by
    /// `PaperCardView`, `BrowseTileView`, and the Related placeholder on
    /// `PaperDetailView`.
    ///
    /// Deliberately *not* used for the two surfaces that hold plots
    /// (`FigureCarouselView`, `HeadlineView`'s thumbnail). Those are a
    /// literal white, because line art on transparency has to stay legible
    /// in dark mode — a different material for a different reason.
    func cardChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return background(Color(.systemBackground), in: shape)
            .overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}
