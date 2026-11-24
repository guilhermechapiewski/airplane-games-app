import GameLogic
import SwiftUI

struct WordWheelView: View {
    @State private var model: WordWheelModel
    @Environment(\.dismiss) private var dismiss

    init(daily: Daily.Day? = nil) {
        _model = State(initialValue: WordWheelModel(daily: daily))
    }

    @State private var listExpanded = false
    @State private var showRanks = false
    @State private var confirmFinish = false
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            let sideBySide = geo.size.width > geo.size.height * 1.15 && geo.size.width >= 680
            Group {
                if let state = model.state, let puzzle = model.puzzle {
                    if sideBySide {
                        HStack(alignment: .top, spacing: 28) {
                            playArea(state: state, puzzle: puzzle)
                                .frame(maxWidth: 520)
                            VStack(spacing: 12) {
                                WordWheelProgress(model: model) { showRanks = true }
                                WordWheelWordList(model: model, state: state, expanded: .constant(true), alwaysExpanded: true)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                            .frame(maxWidth: 420)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isRegular && geo.size.height >= 900 {
                        // Tall iPad: the list stays open above the wheel.
                        VStack(spacing: 16) {
                            WordWheelProgress(model: model) { showRanks = true }
                            WordWheelWordList(model: model, state: state, expanded: .constant(true), alwaysExpanded: true)
                                .frame(height: min(300, geo.size.height * 0.24), alignment: .top)
                            playArea(state: state, puzzle: puzzle)
                        }
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        VStack(spacing: 12) {
                            WordWheelProgress(model: model) { showRanks = true }
                            WordWheelWordList(model: model, state: state, expanded: $listExpanded)
                                .frame(maxHeight: listExpanded ? .infinity : nil, alignment: .top)
                            if !listExpanded {
                                playArea(state: state, puzzle: puzzle)
                            } else if state.isFinished {
                                controls(state: state)
                            }
                        }
                        .frame(maxWidth: isRegular ? 600 : 520)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    ProgressView("Building a wheel…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay {
            if model.celebrating {
                ConfettiView(colors: [WordWheelPalette.colors[0], WordWheelPalette.colors[1], .yellow, .orange, .pink, .mint])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { dailyBanner }
        .overlay { resultOverlay }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { confirmFinish = true } label: {
                    Image(systemName: "flag.checkered").font(.body.weight(.semibold))
                }
                .disabled(!model.canPlay)
                .accessibilityLabel("Finish")
                .accessibilityHint("Ends this wheel and reveals the answers")
                .accessibilityIdentifier("finishWheel")
            }
        }
        .confirmationDialog("Finish this wheel?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish and Reveal Answers", role: .destructive) { model.finish() }
                .accessibilityIdentifier("confirmFinish")
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text(model.daily != nil
                 ? "You'll see the answers you missed. Today's wheel ends here."
                 : "You'll see the answers you missed and your result is saved.")
        }
        .sheet(isPresented: $showRanks) {
            WordWheelRanksSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        .gameChrome(.wordWheel, rules: Self.rules,
                    stats: [StatsVariant(key: nil, title: "Wheels", showsScore: true)],
                    newGame: [NewGameOption(title: "New Wheel", systemImage: "plus.circle") { model.newGame() }],
                    onActiveChange: model.setActive,
                    freshStart: { model.newGame() })
        .task { await model.prepare() }
        .focusable(model.canPlay)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { focused = true }
        .onChange(of: model.isFinished) { _, finished in
            if finished { withAnimation { listExpanded = true } }
        }
        .onChange(of: model.puzzle) { _, _ in listExpanded = false }
    }

    // MARK: Play area

    private func playArea(state: WordWheel.State, puzzle: WordWheel.Puzzle) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            WordWheelEntry(model: model, puzzle: puzzle, input: state.input)
            WordWheelDial(model: model, puzzle: puzzle, ring: state.ring)
                .frame(maxWidth: isRegular ? 540 : 400, maxHeight: isRegular ? 540 : 400)
                .opacity(state.isFinished ? 0.45 : 1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            controls(state: state)
        }
    }

    @ViewBuilder
    private func controls(state: WordWheel.State) -> some View {
        if state.isFinished {
            HStack(spacing: 12) {
                Button("Results") { model.reopenResult() }
                    .buttonStyle(SecondaryButtonStyle())
                if model.daily != nil {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle(color: WordWheelPalette.accent))
                } else {
                    Button("New Wheel") { model.newGame() }
                        .buttonStyle(PrimaryButtonStyle(color: WordWheelPalette.accent))
                        .accessibilityIdentifier("newWheel")
                }
            }
            .frame(minHeight: 56)
        } else {
            HStack(spacing: 12) {
                Button { model.deleteLetter() } label: {
                    Label("Delete", systemImage: "delete.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(WheelControlStyle())
                .disabled(state.input.isEmpty)
                .accessibilityAction(named: "Clear word") { model.clearInput() }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in model.clearInput() })
                .accessibilityIdentifier("deleteLetter")

                Button { model.shuffle() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 30)
                }
                .buttonStyle(WheelControlStyle(round: true))
                .accessibilityLabel("Shuffle")
                .accessibilityHint("Moves the outer letters around")
                .accessibilityIdentifier("shuffle")

                Button { model.submit() } label: {
                    Label("Enter", systemImage: "return").labelStyle(.titleAndIcon)
                }
                .buttonStyle(WheelControlStyle(filled: true))
                .disabled(state.input.isEmpty)
                .accessibilityIdentifier("enterWord")
            }
            .frame(maxWidth: 420)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard model.canPlay, !showRanks, !confirmFinish, !model.showResult else { return .ignored }
        switch press.key {
        case .return:
            model.submit()
            return .handled
        case .delete, .deleteForward:
            model.deleteLetter()
            return .handled
        case .escape:
            model.clearInput()
            return .handled
        case .space:
            model.shuffle()
            return .handled
        default:
            break
        }
        if press.modifiers.contains(.command) { return .ignored }
        if let ch = press.characters.first, press.characters.count == 1, ch.isASCII, ch.isLetter {
            model.type(ch)
            return .handled
        }
        return .ignored
    }

    // MARK: Overlays

    @ViewBuilder private var dailyBanner: some View {
        if model.justSolvedDaily {
            Label("Today's wheel solved! Keep going if you like.", systemImage: "calendar.badge.checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(WordWheelPalette.accent, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.top, 6)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("dailySolvedBanner")
        }
    }

    @ViewBuilder private var resultOverlay: some View {
        if model.showResult, let state = model.state {
            let won = state.rank >= WordWheel.Rank.solved
            ResultOverlay(mood: won ? .win : .neutral,
                          title: state.rank.title,
                          subtitle: subtitle(state),
                          details: details(state),
                          tint: WordWheelPalette.ink) {
                Button("See Answers") { model.dismissResult() }
                    .buttonStyle(PrimaryButtonStyle(color: WordWheelPalette.accent))
                    .accessibilityIdentifier("seeAnswers")
                if model.daily != nil {
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("New Wheel") { model.newGame() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("playAgain")
                }
            }
            .transition(.opacity)
        }
    }

    private func subtitle(_ state: WordWheel.State) -> String {
        let found = state.foundAnswers.count, total = state.puzzle.answers.count
        var text = "You found \(found) of \(total) words"
        if !state.bonusWords.isEmpty { text += " and \(state.bonusWords.count) bonus" }
        text += "."
        if state.foundAllAnswers { text = "You found every word!" }
        if model.daily != nil {
            text += state.rank >= WordWheel.Rank.solved ? " Today's wheel is solved." : " Reach Great to solve a daily wheel."
        }
        return text
    }

    private func details(_ state: WordWheel.State) -> [(String, String)] {
        if model.daily != nil {
            return [("Points", "\(state.score)"), ("Words", "\(state.foundAnswers.count)"),
                    ("Streak", "\(DailyStore.shared.streak(.wordWheel))")]
        }
        return [("Points", "\(state.score)"), ("Words", "\(state.foundAnswers.count)"),
                ("Best", "\(max(model.bestScore ?? 0, state.score))")]
    }

    static let rules = HowToPlay(
        summary: "Spell as many words as you can with the wheel's seven letters.",
        sections: [
            .init(title: "Making words", symbol: "circle.circle", points: [
                "Tap letters (or type on a keyboard), then Enter.",
                "Words have 4 or more letters and must use the center letter.",
                "Letters can be used more than once.",
            ]),
            .init(title: "Points", symbol: "star", points: [
                "A 4-letter word is worth 1 point; longer words score 1 point per letter.",
                "Every wheel has at least one pangram, a word that uses all seven letters: +7 bonus.",
                "Rarer words that aren't on the wheel's list still score, as bonus words.",
            ]),
            .init(title: "Ranks", symbol: "chart.bar.fill", points: [
                "Climb from Starter to Good, Great, Amazing and Genius.",
                "Reaching Great solves the daily wheel and wins a regular wheel.",
                "Tap Finish (the flag) to end a wheel and see the words you missed.",
            ]),
        ]
    )
}

/// Capsule buttons under the wheel.
private struct WheelControlStyle: ButtonStyle {
    var filled = false
    var round = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(filled ? Color.white : Color.primary)
            .padding(.horizontal, round ? 14 : 16)
            .frame(maxWidth: round ? nil : .infinity, minHeight: 52)
            .background {
                if filled {
                    Capsule().fill(WordWheelPalette.accent)
                } else {
                    Capsule().fill(Theme.surface)
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
