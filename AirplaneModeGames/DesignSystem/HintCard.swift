import SwiftUI

/// Explains a hint before revealing it: a title, the reasoning, and a Show Answer button.
/// Shown in place of a game's controls while the board highlights the cells involved.
struct HintCard: View {
    let title: String
    let explanation: String
    var answerTitle = "Show Answer"
    var tint: Color = HintCard.amber
    let onAnswer: () -> Void
    let onClose: () -> Void

    static let amber = Color(hex: 0xF0A500)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundStyle(tint)
                Text(title).font(.headline)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.well, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close hint")
                .accessibilityIdentifier("hintClose")
            }
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hintExplanation")
            Button(action: onAnswer) {
                Text(answerTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(tint)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityIdentifier("hintShowAnswer")
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hintCard")
    }
}
