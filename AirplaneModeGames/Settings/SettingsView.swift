import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var confirmReset = false

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
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle.fill")
                    }
                    .accessibilityIdentifier("aboutLink")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Reset all statistics?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Statistics", role: .destructive) {
                    StatsStore.shared.reset()
                    DailyStore.shared.reset()
                }
            } message: {
                Text("This permanently clears scores, times and streaks for every game.")
            }
        }
    }
}
