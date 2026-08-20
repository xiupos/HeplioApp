import SwiftUI

/// Something a screen can be sorted by. Exists so one toolbar menu can
/// serve both orderings in the app, which have nothing else in common:
/// `InspireHEPClient.SortOrder` asks INSPIRE to rank a query, while
/// `LibrarySort` is a `SortDescriptor` over local SwiftData columns.
protocol SortOption: Hashable {
    var label: String { get }
    var systemImage: String { get }
}

extension View {
    /// The sort menu shared by Search, Explore's browse lists, an
    /// author's papers, and the Library. One place, so they can't drift
    /// into four slightly different menus — and so which orderings a
    /// screen offers stays an argument rather than something re-listed
    /// at each call site.
    ///
    /// An empty `options` draws no button at all, which is how Search
    /// hides it while the field is empty: there's nothing to order yet.
    func sortToolbarItem<Option: SortOption>(
        _ selection: Binding<Option>,
        options: [Option]
    ) -> some View {
        toolbar {
            if !options.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: selection) {
                            ForEach(options, id: \.self) { option in
                                Label(option.label, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}
