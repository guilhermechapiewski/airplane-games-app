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

    static func tap() { guard enabled else { return }; light.impactOccurred() }
    static func impact() { guard enabled else { return }; medium.impactOccurred() }
    static func thud() { guard enabled else { return }; rigid.impactOccurred() }
    static func select() { guard enabled else { return }; selection.selectionChanged() }
    static func success() { guard enabled else { return }; notification.notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; notification.notificationOccurred(.warning) }
    static func error() { guard enabled else { return }; notification.notificationOccurred(.error) }
}
