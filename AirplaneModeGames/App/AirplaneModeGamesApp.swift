import SwiftUI

@main
struct AirplaneModeGamesApp: App {
    @State private var settings = AppSettings.shared

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
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
        }
    }
}
