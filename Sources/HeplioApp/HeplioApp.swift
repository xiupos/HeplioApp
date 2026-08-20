import SwiftUI

@main
struct HeplioApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Nothing else ever notices aged-out cache entries (reads
                // check freshness themselves), so launch is the one moment
                // worth sweeping the directory.
                .task { await ResponseCache.shared.prune() }
        }
        .modelContainer(for: LibraryStore.models)
    }
}
