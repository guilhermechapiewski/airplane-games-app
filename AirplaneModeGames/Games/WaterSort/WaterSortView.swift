import GameLogic
import SwiftUI

struct WaterSortView: View {
    @State private var model = WaterSortModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor

    private var accent: Color { GameID.waterSort.accent }

    var body: some View {
        VStack(spacing: 12) {
            header
            WaterSortBoard(model: model, reduceMotion: reduceMotion, symbols: differentiateWithoutColor,
                           onTap: tap, onPour: pour)
                .id(model.puzzleToken)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tip
            controls
        }
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay { overlay }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-hintDemo") { model.showHint() } }
        #endif
        .gameChrome(.waterSort, rules: Self.rules,
                    stats: [StatsVariant(key: nil, title: "Levels · now on Level \(model.level)")],
                    newGame: [NewGameOption(title: "Restart Level") { restart() }],
                    onActiveChange: model.setActive,
                    freshStart: { model.restart() })
    }

    private func tap(_ tube: Int) {
        model.tap(tube, animated: !reduceMotion)
    }

    private func pour(_ from: Int, _ to: Int) {
        model.pour(from: from, to: to, animated: !reduceMotion)
    }

    private func restart() {
        withAnimation(.easeOut(duration: 0.2)) { model.restart() }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 10) {
            StatPill(title: "Level", value: "\(model.level)", tint: accent)
                .accessibilityIdentifier("levelNumber")
            StatPill(title: "Moves", value: "\(model.moves)")
                .accessibilityIdentifier("movesCount")
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: model.moves)
    }

    /// The suggested pour in words, or a gentle nudge when only the extra tube can help.
    @ViewBuilder private var tip: some View {
        if case let .pour(p)? = model.hint {
            Label("Pour tube \(p.from + 1) into tube \(p.to + 1).", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HintCard.amber)
                .transition(.opacity)
                .accessibilityIdentifier("hintTip")
        } else if model.isThinking {
            Label("Thinking…", systemImage: "lightbulb")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        } else if model.needsExtraTube {
            Label("No pours left. Add the extra tube.", systemImage: "lightbulb")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    /// A recovery hint (extra tube, undo, restart) is explained in place of the tools.
    private var recoveryHint: WaterSort.Hint? {
        if case .pour? = model.hint { return nil }
        return model.hint
    }

    private var controls: some View {
        toolRow
            .opacity(recoveryHint == nil ? 1 : 0)
            .allowsHitTesting(recoveryHint == nil)
            .accessibilityHidden(recoveryHint != nil)
            .overlay(alignment: .bottom) {
                if let hint = recoveryHint {
                    HintCard(title: "Can't be sorted from here", explanation: Self.recoveryText(hint),
                             answerTitle: Self.answerTitle(hint), tint: HintCard.amber,
                             onAnswer: { withAnimation(.easeOut(duration: 0.2)) { model.applyHint() } },
                             onClose: { model.dismissHint() })
                        .frame(maxWidth: 520)
                }
            }
    }

    static func recoveryText(_ hint: WaterSort.Hint) -> String {
        switch hint {
        case .pour: ""
        case .addExtraTube: "No way to sort these tubes from here, but there is with one more empty tube."
        case let .undo(steps): steps == 1
            ? "Your last pour closed every way out. Take it back and you're on track again."
            : "One of your recent pours closed every way out. Undo the last \(steps) pours to get back on track."
        case .restart: "No way out was found from here or from your recent pours. Start the level over: every puzzle can be sorted."
        }
    }

    static func answerTitle(_ hint: WaterSort.Hint) -> String {
        switch hint {
        case .pour: "OK"
        case .addExtraTube: "Add Extra Tube"
        case let .undo(steps): steps == 1 ? "Undo 1 Pour" : "Undo \(steps) Pours"
        case .restart: "Restart Level"
        }
    }

    private var toolRow: some View {
        HStack(spacing: 20) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward",
                       badge: model.moves > 0 ? "\(model.moves)" : nil) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.undo() }
            }
            .disabled(!model.canUndo)
            ToolButton(title: "Extra Tube", systemImage: model.canAddTube ? "plus.rectangle.portrait" : "checkmark.rectangle.portrait",
                       isActive: model.needsExtraTube, tint: accent) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { model.addExtraTube() }
            }
            .disabled(!model.canAddTube)
            .accessibilityHint(model.canAddTube ? "Adds one empty tube. Once per level." : "Already used on this level.")
            ToolButton(title: "Hint", systemImage: "lightbulb", isActive: model.hint != nil || model.isThinking,
                       tint: HintCard.amber) {
                withAnimation(.easeOut(duration: 0.2)) { model.showHint() }
            }
            .disabled(model.state.isSolved)
            .accessibilityHint("Suggests the next pour.")
            .accessibilityIdentifier("hintButton")
            ToolButton(title: "Restart", systemImage: "arrow.counterclockwise") { restart() }
                .disabled(model.moves == 0 && !model.state.extraTubeUsed)
        }
    }

    static func movesText(_ n: Int) -> String { n == 1 ? "1 move" : "\(n) moves" }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        if model.showWin {
            ResultOverlay(mood: .win, title: "Sorted!",
                          subtitle: "Level \(model.solvedLevel) solved in \(Self.movesText(model.solvedMoves)).",
                          details: [("Moves", "\(model.solvedMoves)"), ("Solved", "\(model.levelsSolved)")],
                          tint: accent) {
                Button("Next Level") { withAnimation(.easeOut(duration: 0.25)) { model.nextLevel() } }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                Button("Back to Games") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        } else if model.showStuck {
            ResultOverlay(mood: .neutral, title: "No pours left",
                          subtitle: "Undo a few pours or start over. Every puzzle can be sorted.",
                          details: [("Moves", "\(model.moves)")],
                          tint: accent) {
                Button("Undo") { withAnimation(.easeOut(duration: 0.2)) { model.undo() } }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                Button("Restart") { restart() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity.animation(.easeOut(duration: 0.25).delay(reduceMotion ? 0 : 0.5)))
        }
    }

    static let rules = HowToPlay(
        summary: "Pour the liquids between tubes until every tube holds just one color.",
        sections: [
            .init(title: "Pouring", symbol: "drop.fill", points: [
                "Tap a tube to pick it up, then tap another tube to pour into it.",
                "You can pour onto the same color or into an empty tube, as much as fits. A tube holds four layers.",
                "A full tube of one color is done and gets a stopper.",
            ]),
            .init(title: "Help", symbol: "lifepreserver", points: [
                "Undo takes back pours, as many as you like.",
                "Each level gives you one extra empty tube when you need more room.",
                "Every puzzle can be solved. No clock: take your time.",
                "Tap Hint to see the next pour. If a pour has closed every way out, Hint tells you how many to undo. Hints are free.",
            ]),
            .init(title: "Levels", symbol: "stairs", points: [
                "Levels slowly add colors, from 3 up to 12. Solve one to unlock the next.",
            ]),
            .init(title: "Tips", symbol: "graduationcap", points: [
                "An empty tube is your most valuable space. Fill it only when you have a plan for it.",
                "Pour onto a matching color before reaching for an empty tube.",
                "Aim to finish one color at a time: a completed tube is out of your way for good.",
                "Dig out colors buried under just one or two layers first; deeply buried ones can wait.",
                "Before pouring into an empty tube, check that more of that color is within reach.",
            ]),
        ]
    )
}
