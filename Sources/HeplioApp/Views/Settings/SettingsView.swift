import SwiftUI

/// App-wide settings, presented as a sheet from the Library tab's toolbar
/// — the same place Music keeps its account/settings button. A plain
/// `Form`, like Settings.app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cacheSize: Int64 = 0
    @State private var isConfirmingClear = false
    @State private var isClearing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Cached Papers", value: cacheSize.formatted(.byteCount(style: .file)))
                    Button("Clear Cache", role: .destructive) {
                        isConfirmingClear = true
                    }
                    .disabled(isClearing || cacheSize == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Papers you open are kept for a day so they reappear instantly and stay within INSPIRE-HEP's request limits. Clearing frees the space; anything you open again is downloaded again.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link("inspirehep.net", destination: URL(string: "https://inspirehep.net")!)
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
        }
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
}
