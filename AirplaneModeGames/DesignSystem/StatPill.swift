import SwiftUI

/// Compact labelled value (Score, Best, Time, Mines...) shown above game boards.
struct StatPill: View {
    let title: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint.map { $0.opacity(0.9) } ?? .secondary)
                .tracking(0.6)
                // Shrink rather than break mid-word ("MOVE/S") when large text fills a row of pills.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
