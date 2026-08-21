import SwiftUI
import SwiftData

/// App-wide settings, presented as a sheet from the Library tab's toolbar
/// — the same place Music keeps its account/settings button. A plain
/// `Form`, like Settings.app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var cacheSize: Int64 = 0
    @State private var isConfirmingClear = false
    @State private var isClearing = false

    /// Plain `Int` rather than `Int64`: `@AppStorage` supports the former
    /// and not the latter, and no plausible budget comes near the limit.
    @AppStorage(ResponseCache.budgetKey) private var budget = ResponseCache.defaultBudget

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Cached Papers", value: cacheSize.formatted(.byteCount(style: .file)))

                    Picker("Maximum Size", selection: $budget) {
                        ForEach(Self.budgetChoices, id: \.self) { bytes in
                            Text(Self.budgetLabel(bytes)).tag(bytes)
                        }
                    }

                    Button("Clear Cache", role: .destructive) {
                        isConfirmingClear = true
                    }
                    .disabled(isClearing || cacheSize == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Papers you open are kept for a day so they reappear instantly and stay within INSPIRE-HEP's request limits. Once the cache passes its maximum size, the oldest entries are removed first — papers in your library are kept longest, so they stay readable offline.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link("inspirehep.net", destination: URL(string: "https://inspirehep.net")!)
                    Link("Source on GitHub", destination: URL(string: "https://github.com/xiupos/HeplioApp")!)
                } header: {
                    Text("About")
                } footer: {
                    Text("Heplio is an unofficial client for INSPIRE-HEP and isn't affiliated with it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear Cached Papers?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear Cache", role: .destructive) {
                    Task { await clearCache() }
                }
            } message: {
                Text("Papers will be downloaded again the next time you open them.")
            }
            .task { await refreshCacheSize() }
            // Applying it here rather than waiting for the next launch:
            // someone who has just lowered the limit because they want the
            // space back should see the number above them drop, not a
            // promise that it will.
            .task(id: budget) {
                await ResponseCache.shared.enforceBudget(
                    protecting: modelContext.cacheKeysWorthKeeping()
                )
                await refreshCacheSize()
            }
        }
    }

    /// A response is 20–240 KB, so even the smallest of these holds a few
    /// hundred of them. `0` means no limit, matching `ResponseCache.budget`.
    private static let budgetChoices = [
        50 * 1024 * 1024,
        200 * 1024 * 1024,
        500 * 1024 * 1024,
        1024 * 1024 * 1024,
        0
    ]

    private static func budgetLabel(_ bytes: Int) -> String {
        bytes == 0 ? "No Limit" : Int64(bytes).formatted(.byteCount(style: .file))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func refreshCacheSize() async {
        cacheSize = await ResponseCache.shared.diskSize()
    }

    private func clearCache() async {
        isClearing = true
        defer { isClearing = false }
        await ResponseCache.shared.clear()
        await refreshCacheSize()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: LibraryStore.models, inMemory: true)
}
