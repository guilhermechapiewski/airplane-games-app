import SwiftUI
import GameLogic

struct NonogramsPuzzleView: View {
    let model: NonogramsPuzzleModel
    let onSelect: (Nonograms.Puzzle) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = GameID.nonograms.accent

    var body: some View {
        VStack(spacing: 12) {
            header
                .frame(maxWidth: 720)
            NonogramBoard(model: model)
                .frame(maxWidth: 720, maxHeight: .infinity)
                .overlay(alignment: .bottom) { toast }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay { overlay }
        .gameChrome(.nonograms, rules: NonogramsView.rules,
                    stats: NonogramsPuzzleModel.statsVariants,
                    newGame: [
                        NewGameOption(title: "Restart Puzzle", systemImage: "arrow.counterclockwise") {
                            withAnimation { model.restart() }
                        },
                        NewGameOption(title: "Next Puzzle", systemImage: "forward.end") { goToNext() },
                    ],
                    onActiveChange: model.setActive)
    }

    private func goToNext() {
        if let next = NonogramsProgress.shared.nextPuzzle(of: model.size, after: model.puzzle) {
            onSelect(next)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.size.title.uppercased()) · \(model.puzzle.width)×\(model.puzzle.height)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(accent.opacity(0.9))
                Text(model.isSolved ? model.puzzle.title : "Puzzle \(model.number)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                    .id(model.isSolved)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: model.isSolved)

            if !model.isSolved || model.justSolved {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    StatPill(title: "Time", value: (model.isSolved ? model.finalTime : model.clock.elapsed(at: context.date)).clockString)
                }
            }
            if let best = model.bestTime {
                StatPill(title: "Best", value: best.clockString)
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if model.isSolved && !model.justSolved {
            HStack(spacing: 12) {
                Button("Play Again") { withAnimation { model.restart() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Next Puzzle") { goToNext() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
            }
        } else {
            HStack(spacing: 10) {
                ToolToggle(tool: Binding(get: { model.tool }, set: { model.setTool($0) }))
                Spacer(minLength: 0)
                ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                    withAnimation(.easeOut(duration: 0.15)) { model.undo() }
                }
                .disabled(!model.canUndo)
                ToolButton(title: "Hint", systemImage: "lightbulb", badge: model.hintsUsed > 0 ? "\(model.hintsUsed)" : nil,
                           tint: NonoPalette.hint) {
                    withAnimation(.easeOut(duration: 0.2)) { model.hint() }
                }
                .disabled(model.isSolved)
                ToolButton(title: "Check", systemImage: "checkmark.circle") {
                    withAnimation(.easeOut(duration: 0.2)) { model.check() }
                }
                .disabled(model.isSolved)
            }
            .frame(maxWidth: 560)
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.checkMessage {
            Label(message, systemImage: model.flagged.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.flagged.isEmpty ? Color.green : NonoPalette.mistake)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    // MARK: Result

    @ViewBuilder private var overlay: some View {
        if model.showResult {
            let color = Color(hex: model.puzzle.color)
            ResultOverlay(mood: .win, title: model.puzzle.title,
                          subtitle: model.isNewBest ? "Picture revealed — new best time!" : "Picture revealed!",
                          details: [("Time", model.finalTime.clockString)] + (model.hintsUsed > 0 ? [("Hints", "\(model.hintsUsed)")] : []),
                          tint: color) {
                PixelArtView(width: model.puzzle.width, height: model.puzzle.height,
                             cells: model.puzzle.solution, color: color)
                    .frame(width: 96, height: 96)
                    .padding(10)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.bottom, 4)
                Button("Next Puzzle") { goToNext() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("nextPuzzleButton")
                Button("All Puzzles") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        }
    }
}

/// Two-segment Fill / Cross switch; tapping anywhere flips it.
private struct ToolToggle: View {
    @Binding var tool: Nonograms.Tool
    @Namespace private var pill

    var body: some View {
        Button(action: flip) {
            HStack(spacing: 2) {
                segment(.fill, title: "Fill", symbol: "square.fill")
                segment(.cross, title: "Cross", symbol: "xmark")
            }
            .padding(4)
            .background(Theme.well, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityLabel("Marking tool")
        .accessibilityValue(tool == .fill ? "Fill" : "Cross")
        .accessibilityHint("Switches between filling cells and crossing them out")
        .accessibilityIdentifier("toolToggle")
    }

    private func flip() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tool = tool == .fill ? .cross : .fill }
        Feedback.play(.select)
    }

    private func segment(_ value: Nonograms.Tool, title: String, symbol: String) -> some View {
        let selected = tool == value
        return Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? .white : .secondary)
            .background {
                if selected {
                    Capsule().fill(value == .fill ? GameID.nonograms.accent : Color(hex: 0x6E7590))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
    }
}
