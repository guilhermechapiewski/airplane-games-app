import SwiftUI

struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/guilhermechapiewski/airplane-games-app")!
    private static let issuesURL = URL(string: "https://github.com/guilhermechapiewski/airplane-games-app/issues/new")!

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
            }
            Section {
                notice("Your privacy", systemImage: "lock.shield.fill") {
                    Text("Airplane Games works entirely offline. No Wi‑Fi needed, no ads, no accounts, no analytics and no network access. Your games and statistics never leave this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                notice("Open source", systemImage: "chevron.left.forwardslash.chevron.right") {
                    Text("Released under the MIT License.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("github.com/guilhermechapiewski/airplane-games-app", destination: Self.repositoryURL)
                        .font(.footnote)
                        .accessibilityLabel("Source code on GitHub")
                }
            }
            Section {
                Link(destination: Self.issuesURL) {
                    Label("Report a Bug or Send Feedback", systemImage: "ladybug.fill")
                }
                .accessibilityIdentifier("reportBugLink")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notice<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.headline)
            content()
        }
        .padding(.vertical, 4)
    }
}
