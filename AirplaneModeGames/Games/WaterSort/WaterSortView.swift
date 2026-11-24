import GameLogic
import SwiftUI

struct WaterSortView: View {
    @State private var model: WaterSortModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor

    init(daily: Daily.Day? = nil) {
        _model = State(initialValue: WaterSortModel(daily: daily))
    }

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
        .gameChrome(.waterSort, rules: Self.rules,
                    stats: [StatsVariant(key: nil, title: model.isDaily ? "Levels" : "Levels · now on Level \(model.level)")],
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
            if let day = model.daily {
                StatPill(title: "Daily", value: Self.dayString(day), tint: accent)
                    .accessibilityIdentifier("levelNumber")
            } else {
                StatPill(title: "Level", value: "\(model.level)", tint: accent)
                    .accessibilityIdentifier("levelNumber")
            }
            StatPill(title: "Moves", value: "\(model.moves)")
                .accessibilityIdentifier("movesCount")
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: model.moves)
    }

    /// A gentle nudge when only the extra tube can help.
    @ViewBuilder private var tip: some View {
        if model.needsExtraTube {
            Label("No pours left. Add the extra tube.", systemImage: "lightbulb")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
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
            ToolButton(title: "Restart", systemImage: "arrow.counterclockwise") { restart() }
                .disabled(model.moves == 0 && !model.state.extraTubeUsed)
        }
    }

    static func movesText(_ n: Int) -> String { n == 1 ? "1 move" : "\(n) moves" }

    static func dayString(_ day: Daily.Day) -> String {
        let date = Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        return date?.formatted(.dateTime.month(.abbreviated).day()) ?? day.key
    }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        if model.showWin {
            if let _ = model.daily {
                ResultOverlay(mood: .win, title: "Sorted!",
                              subtitle: "Today's puzzle, solved in \(Self.movesText(model.solvedMoves)).",
                              details: [("Moves", "\(model.solvedMoves)"),
                                        ("Time", model.clock.elapsed().clockString),
                                        ("Streak", "🔥 \(DailyStore.shared.streak(.waterSort))")],
                              tint: accent) {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                }
                .transition(.opacity)
            } else {
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
            }
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
            ]),
            .init(title: "Levels & daily", symbol: "calendar", points: [
                "Levels slowly add colors, from 3 up to 12. Solve one to unlock the next.",
                "Today's Puzzle is the same for everyone and keeps your daily streak.",
            ]),
        ]
    )
}
