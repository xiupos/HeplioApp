import SwiftUI

/// Navigation value for a paper's full author list. Carries the record id
/// rather than the authors themselves: this gets hashed and compared on
/// every path change, and a collaboration paper's list runs to a few
/// thousand names. Re-reading the record costs nothing — it's the one
/// `PaperDetailView` just loaded, so it comes straight from the cache.
struct AuthorListDestination: Hashable {
    let paperID: Int
}

/// Every author on a paper, pushed from the "Show All N Authors" button —
/// the same shape as the History list, and searchable because the papers
/// that need this screen have thousands of names on them. This is what
/// INSPIRE's own site puts behind its "show all authors" control.
struct AuthorListView: View {
    let destination: AuthorListDestination

    @State private var authors: LoadState<[Paper.Author]> = .loading
    @State private var filter = ""

    private var matches: [Paper.Author] {
        let all = authors.value ?? []
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        return all.filter {
            $0.fullName.localizedCaseInsensitiveContains(text)
                || $0.affiliations.contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }

    var body: some View {
        List {
            if authors.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: filter)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(matches) { author in
                    NavigationLink(value: author) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(author.fullName)
                            if let affiliation = author.affiliations.first {
                                Text(affiliation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .searchable(
            text: $filter,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name or Affiliation"
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: destination.paperID) {
            authors = await .load {
                try await PaperService.shared.details(id: destination.paperID).authors
            }
        }
    }

    private var title: String {
        guard let count = authors.value?.count else { return "Authors" }
        return count == 1 ? "1 Author" : "\(count) Authors"
    }
}

#Preview {
    NavigationStack {
        AuthorListView(destination: AuthorListDestination(paperID: Paper.preview.id))
    }
    .modelContainer(for: LibraryStore.models, inMemory: true)
}
