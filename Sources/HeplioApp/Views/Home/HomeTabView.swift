import SwiftUI

struct HomeTabView: View {
    var body: some View {
        NavigationStack {
            List {
                ContentUnavailableView(
                    "No Recommendations Yet",
                    systemImage: "sparkles",
                    description: Text("Save papers to get recommendations in related fields")
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeTabView()
}
