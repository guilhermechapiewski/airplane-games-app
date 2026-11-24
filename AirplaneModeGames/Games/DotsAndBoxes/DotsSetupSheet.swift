import SwiftUI
import GameLogic

/// Choose the opponent (a computer level or a friend) and the board size.
struct DotsSetupSheet: View {
    let model: DotsAndBoxesModel
    @State private var setup = DotsAndBoxesModel.lastSetup
    @Environment(\.dismiss) private var dismiss

    private let accent = DotsTheme.accent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        GameBadge(game: .dotsAndBoxes, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New Game").font(.title2.bold())
                            Text("Play the computer or a friend on this device.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        opponentCard(.computer, symbol: "cpu", detail: "Three levels")
                        opponentCard(.friend, symbol: "person.2.fill", detail: "Share this device")
                    }

                    section("Board") {
                        HStack(spacing: 10) {
                            ForEach(DotsSetup.sizes, id: \.self) { size in
                                sizeCard(size)
                            }
                        }
                    }

                    if setup.isComputer {
                        section("Computer") {
                            VStack(spacing: 8) {
                                ForEach(DotsAndBoxes.Level.allCases) { level in
                                    levelRow(level)
                                }
                            }
                        }
                    }

                    Button {
                        model.newGame(setup)
                        dismiss()
                    } label: {
                        Text("Start Game").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("setup.start")
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: setup.opponent)
            }
            .background(Theme.background)
            .navigationTitle("Dots and Boxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("setup.cancel")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func opponentCard(_ opponent: DotsSetup.Opponent, symbol: String, detail: String) -> some View {
        let isOn = setup.opponent == opponent
        return Button {
            setup.opponent = opponent
            Feedback.play(.select)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isOn ? .white : accent)
                    .frame(width: 54, height: 54)
                    .background(isOn ? accent : accent.opacity(0.14), in: Circle())
                Text(opponent.title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? accent : Theme.hairline, lineWidth: isOn ? 2.5 : 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(opponent.title). \(detail)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("setup.opponent.\(opponent.rawValue)")
    }

    private func sizeCard(_ size: Int) -> some View {
        let isOn = setup.size == size
        return Button {
            setup.size = size
            Feedback.play(.select)
        } label: {
            VStack(spacing: 8) {
                DotsMiniGrid(size: size, color: isOn ? accent : .secondary)
                    .frame(width: 44, height: 44)
                Text("\(size)×\(size)").font(.headline).monospacedDigit()
                Text(size == 3 ? "Quick" : (size == 4 ? "Classic" : "Long"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? accent : Theme.hairline, lineWidth: isOn ? 2.5 : 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(size) by \(size) boxes")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("setup.size.\(size)")
    }

    private func levelRow(_ level: DotsAndBoxes.Level) -> some View {
        let isOn = setup.level == level
        let record = model.record(for: level)
        return Button {
            setup.level = level
            Feedback.play(.select)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule()
                            .fill(i <= level.rawValue ? accent : accent.opacity(0.18))
                            .frame(width: 6, height: 8 + CGFloat(i) * 5)
                    }
                }
                .frame(width: 32, height: 26, alignment: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(level.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(level.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if record.total > 0 {
                    Text("\(record.wins)W · \(record.losses)L · \(record.ties)T")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? accent : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.title). \(level.subtitle)."
                            + (record.total > 0 ? " Record: \(record.wins) wins, \(record.losses) losses, \(record.ties) ties." : ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("setup.level.\(level.rawValue)")
    }
}

/// A tiny dot grid with a few lines and a claimed box, previewing a board size.
struct DotsMiniGrid: View {
    let size: Int
    let color: Color

    var body: some View {
        Canvas { context, canvasSize in
            let r: CGFloat = size > 4 ? 1.6 : 2.2
            let step = (canvasSize.width - r * 2) / CGFloat(size)
            context.translateBy(x: r, y: r)
            // One claimed box in the corner.
            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: step, height: step), cornerRadius: 2),
                         with: .color(color.opacity(0.25)))
            var lines = Path()
            lines.move(to: CGPoint(x: 0, y: step))
            lines.addLine(to: .zero)
            lines.addLine(to: CGPoint(x: step, y: 0))
            lines.addLine(to: CGPoint(x: step, y: step))
            lines.addLine(to: CGPoint(x: 0, y: step))
            context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: r * 0.9, lineCap: .round, lineJoin: .round))
            for row in 0...size {
                for col in 0...size {
                    let p = CGPoint(x: CGFloat(col) * step, y: CGFloat(row) * step)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
