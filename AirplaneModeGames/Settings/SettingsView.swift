import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle(isOn: $settings.soundEnabled) { Label("Sound Effects", systemImage: "speaker.wave.2.fill") }
                    Toggle(isOn: $settings.hapticsEnabled) { Label("Haptics", systemImage: "iphone.radiowaves.left.and.right") }
                }
                Section("Appearance") {
                    Picker(selection: $settings.appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Theme", systemImage: "circle.lefthalf.filled")
                    }
                }
                Section {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Reset All Statistics", systemImage: "trash")
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Your privacy", systemImage: "lock.shield.fill").font(.headline)
                        Text("Airplane Games works entirely offline. It has no ads, no accounts, no analytics and no network access. Your games and statistics never leave this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Open source", systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                        Text("Released under the MIT License.\ngithub.com/guilhermechapiewski")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Reset all statistics?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Statistics", role: .destructive) { StatsStore.shared.reset() }
            } message: {
                Text("This permanently clears scores, times and streaks for every game.")
            }
        }
    }
}
