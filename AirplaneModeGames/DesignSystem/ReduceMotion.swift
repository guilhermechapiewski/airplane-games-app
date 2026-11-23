import SwiftUI

extension EnvironmentValues {
    /// The app's effective Reduce Motion setting. Views read this instead of
    /// `accessibilityReduceMotion` so UI tests can opt in too.
    @Entry var reduceMotion = false
    /// The app's effective "Differentiate Without Color" setting (read instead of
    /// `accessibilityDifferentiateWithoutColor`, so DEBUG builds can force it for screenshots).
    @Entry var differentiateWithoutColor = false
}

enum LaunchOptions {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    #if DEBUG
    /// `-differentiateWithoutColor` previews that accessibility setting in the simulator.
    static let forcesDifferentiateWithoutColor = ProcessInfo.processInfo.arguments.contains("-differentiateWithoutColor")
    #else
    static let forcesDifferentiateWithoutColor = false
    #endif
}

private struct ReduceMotionProvider: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiateWithoutColor

    func body(content: Content) -> some View {
        // Under UI tests, looping SwiftUI animations keep the app from ever going idle,
        // which makes XCUITest stall before every interaction.
        content
            .environment(\.reduceMotion, systemReduceMotion || LaunchOptions.isUITesting)
            .environment(\.differentiateWithoutColor,
                         systemDifferentiateWithoutColor || LaunchOptions.forcesDifferentiateWithoutColor)
    }
}

extension View {
    /// Publishes `\.reduceMotion` to this subtree. Apply once at the root.
    func providesReduceMotion() -> some View { modifier(ReduceMotionProvider()) }
}
