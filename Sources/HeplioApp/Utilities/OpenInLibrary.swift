import SwiftUI

extension EnvironmentValues {
    /// Present when (and only when) a paper is being viewed inside a
    /// modal sheet that has its own push navigation — currently
    /// `HistoryView` — pushed there by `LibraryTabView` so tapping it
    /// dismisses the sheet and re-opens the same paper on the Library
    /// tab's own, full-width `NavigationStack`.
    ///
    /// Like `paperOrigin`, this has to be set on the sheet's root view
    /// (an ancestor of its `NavigationStack`), not on a view inside it —
    /// pushed destinations only inherit environment from above the stack.
    @Entry var openInLibrary: ((Paper) -> Void)?
}
