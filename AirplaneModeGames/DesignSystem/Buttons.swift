import SwiftUI

/// Large, rounded, filled button used for primary actions in game overlays.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minWidth: 160)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtle capsule button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.well, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Icon + caption tool button used in game control bars (Undo, Hint, Pencil...).
struct ToolButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    var badge: String?
    var tint: Color = .accentColor
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 40)
                        .background(isActive ? tint.opacity(0.18) : Theme.well, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(isActive ? tint : .primary)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(tint, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    // At the largest text sizes a row of tools has no room: shrink, never break mid-word.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Gentle press-down scale for custom buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
