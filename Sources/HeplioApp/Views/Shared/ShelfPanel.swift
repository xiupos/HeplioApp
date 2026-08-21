import SwiftUI

extension View {
    /// The rounded gray backdrop one shelf sits on — Explore's grids and
    /// Trending carousel, and every row of Home.
    ///
    /// `secondarySystemBackground` behind `systemBackground`-carded
    /// content is the pairing `PaperDetailView` already uses for its
    /// related-content zone; broken into one panel per shelf rather than
    /// one continuous field, it gives the grouped-section rhythm
    /// Settings.app and Reminders have without introducing a colour or a
    /// material of its own.
    ///
    /// In one place because two screens draw it and a third will: this is
    /// the same reason `cardChrome()` and `KickerText` exist rather than
    /// three hand-kept copies each.
    /// - Parameter tinted: Draws the panel in a wash of the app's accent
    ///   colour instead of plain gray. Home uses it to separate the
    ///   shelves that are *about the reader* — For You, Because You Read,
    ///   More By — from the ones that would look the same on anyone's
    ///   screen. Two treatments, not ten: a colour per shelf kind would
    ///   be a palette, which this app deliberately doesn't have, and the
    ///   accent is whatever the system already gives every control here.
    ///
    ///   The wash is deliberately barely-there. It has to read as a
    ///   surface, not as a highlight — anything strong enough to notice
    ///   on its own would fight the cards sitting on top of it, which are
    ///   `systemBackground` and expect a quiet backdrop.
    func shelfPanel(tinted: Bool = false) -> some View {
        padding(.vertical)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if tinted {
                    // Over the gray rather than instead of it, so the
                    // panel keeps the same value in dark mode — the
                    // accent alone at this opacity vanishes on black.
                    shape.fill(Color(.secondarySystemBackground))
                        .overlay { shape.fill(Color.accentColor.opacity(0.10)) }
                } else {
                    shape.fill(Color(.secondarySystemBackground))
                }
            }
            .padding(.horizontal)
    }
}
