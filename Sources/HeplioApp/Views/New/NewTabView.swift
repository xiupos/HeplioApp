import SwiftUI

struct NewTabView: View {
    var body: some View {
        NavigationStack {
            List {
                ContentUnavailableView(
                    "New Papers",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Recently published literature will appear here")
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("New")
        }
    }
}

#Preview {
    NewTabView()
}
