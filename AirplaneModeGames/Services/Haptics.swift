import UIKit

/// Thin wrapper over UIKit feedback generators that respects the user's setting.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    private static var enabled: Bool { AppSettings.shared.hapticsEnabled }

    // Each call re-arms its generator with `prepare()` so the Taptic Engine stays awake for the
    // next touch; an idle engine otherwise adds a perceptible delay to the first haptic.
    static func tap() { guard enabled else { return }; light.impactOccurred(); light.prepare() }
    static func impact() { guard enabled else { return }; medium.impactOccurred(); medium.prepare() }
    static func thud() { guard enabled else { return }; rigid.impactOccurred(); rigid.prepare() }
    static func select() { guard enabled else { return }; selection.selectionChanged(); selection.prepare() }
    static func success() { guard enabled else { return }; notification.notificationOccurred(.success); notification.prepare() }
    static func warning() { guard enabled else { return }; notification.notificationOccurred(.warning); notification.prepare() }
    static func error() { guard enabled else { return }; notification.notificationOccurred(.error); notification.prepare() }

    /// Wakes the generators a game is about to use (call when a game screen appears).
    static func prepare() {
        guard enabled else { return }
        light.prepare(); medium.prepare(); selection.prepare()
    }
}
