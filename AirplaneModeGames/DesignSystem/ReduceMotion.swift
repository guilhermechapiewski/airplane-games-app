import SwiftUI

extension EnvironmentValues {
    /// The app's effective Reduce Motion setting. Views read this instead of
    /// `accessibilityReduceMotion` so UI tests can opt in too.
    @Entry var reduceMotion = false
}

enum LaunchOptions {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
}

private struct ReduceMotionProvider: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        // Under UI tests, looping SwiftUI animations keep the app from ever going idle,
        // which makes XCUITest stall before every interaction.
        content.environment(\.reduceMotion, systemReduceMotion || LaunchOptions.isUITesting)
    }
}

extension View {
    /// Publishes `\.reduceMotion` to this subtree. Apply once at the root.
    func providesReduceMotion() -> some View { modifier(ReduceMotionProvider()) }
}
