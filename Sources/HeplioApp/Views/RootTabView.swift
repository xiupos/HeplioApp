import SwiftUI
import SwiftData

struct RootTabView: View {
    /// Read here rather than in `HeplioApp`: the container is installed
    /// on the scene, so the `App` itself is outside it and would get an
    /// empty context.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeTabView()
            }

            Tab("New", systemImage: "clock.arrow.circlepath") {
                NewTabView()
            }

            Tab("Explore", systemImage: "safari") {
                ExploreTabView()
            }

            Tab("Library", systemImage: "square.stack.fill") {
                LibraryTabView()
            }

            Tab(role: .search) {
                SearchTabView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task { modelContext.backfillPaperMetadata() }
    }
}

#Preview {
    RootTabView()
}
