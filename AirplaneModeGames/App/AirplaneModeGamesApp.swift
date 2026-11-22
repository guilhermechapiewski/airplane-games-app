import SwiftUI

@main
struct AirplaneModeGamesApp: App {
    @State private var settings = AppSettings.shared

    init() {
        if LaunchOptions.isUITesting {
            // UI tests start from a clean slate without sounds.
            GameStore.shared.removeAll()
            AppSettings.shared.soundEnabled = false
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(settings.appearance.colorScheme)
                .fontDesign(.rounded)
                .providesReduceMotion()
                .task {
                    // Build the sound effects after the first frame instead of on the first tap.
                    try? await Task.sleep(for: .milliseconds(300))
                    SoundEngine.shared.warmUp()
                }
        }
    }
}
