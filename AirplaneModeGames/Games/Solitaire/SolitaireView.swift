import SwiftUI
import GameLogic

struct SolitaireView: View {
    @State private var model: SolitaireModel
    @Environment(\.dismiss) private var dismiss

    init(daily: Daily.Day? = nil) {
        _model = State(initialValue: SolitaireModel(daily: daily))
    }
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let accent = GameID.solitaire.accent

    var body: some View {
        VStack(spacing: sizeClass == .regular ? 18 : 10) {
            header
            SolitaireTable(model: model, showsCascade: showsCascade)
                .frame(maxWidth: sizeClass == .regular ? 900 : .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { autoCompleteButton }
                .overlay { preparingBadge }
            controls
        }
        .padding(.horizontal, sizeClass == .regular ? 24 : 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(FeltBackground().ignoresSafeArea())
        .overlay { overlay }
        .gameChrome(.solitaire, rules: Self.rules,
                    stats: Solitaire.DrawMode.allCases.map {
                        StatsVariant(key: $0.rawValue, title: $0.title, showsScore: true, showsTime: true)
                    },
                    newGame: Solitaire.DrawMode.allCases.map { mode in
                        NewGameOption(title: mode.title, systemImage: mode == .draw1 ? "1.square" : "3.square") {
                            model.newGame(mode)
                        }
                    },
                    onActiveChange: model.setActive,
                    freshStart: { model.newGame() })
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in model.reduceMotion = value }
        .animation(.easeOut(duration: 0.25), value: model.showStuck)
        .animation(.easeOut(duration: 0.25), value: model.phase)
    }

    private var showsCascade: Bool {
        !reduceMotion && (model.phase == .celebrating || model.phase == .won) && model.state.isWon
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 8) {
            StatPill(title: "Score", value: "\(model.displayScore)", tint: accent)
            StatPill(title: "Moves", value: "\(model.state.moveCount)")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatPill(title: "Time", value: model.clock.elapsed(at: context.date).clockString)
            }
            Spacer(minLength: 0)
            Text(model.drawMode.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.22), in: Capsule())
                .accessibilityLabel("Mode: \(model.drawMode.title)")
        }
        .frame(maxWidth: sizeClass == .regular ? 900 : .infinity)
        .animation(.snappy, value: model.displayScore)
        .animation(.snappy, value: model.state.moveCount)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                withAnimation(SolitaireModel.cardAnimation) { model.undo() }
            }
            .disabled(!model.canUndo)
            ToolButton(title: "Hint", systemImage: "lightbulb", isActive: model.hint != nil, tint: SolitairePalette.hint) {
                withAnimation(.easeOut(duration: 0.2)) { model.showHint() }
            }
            .disabled(!model.isInteractive)
            Menu {
                if model.daily != nil {
                    Button { model.newGame() } label: { Label("Restart Today's Deal", systemImage: "arrow.counterclockwise") }
                } else {
                    ForEach(Solitaire.DrawMode.allCases) { mode in
                        Button { model.newGame(mode) } label: {
                            Label(mode.title, systemImage: mode == .draw1 ? "1.square" : "3.square")
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 40)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.primary)
                    Text(model.daily != nil ? "Restart" : "New")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            .accessibilityLabel("New Game")
            .accessibilityIdentifier("newGameMenu")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    @ViewBuilder private var autoCompleteButton: some View {
        if model.canAutoComplete {
            Button {
                model.autoComplete()
            } label: {
                Label("Auto-Complete", systemImage: "wand.and.stars")
            }
            .buttonStyle(PrimaryButtonStyle(color: accent))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.bottom, 12)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
            .accessibilityIdentifier("autoComplete")
        }
    }

    @ViewBuilder private var preparingBadge: some View {
        if model.phase == .preparing {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Shuffling…").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.3), in: Capsule())
            .transition(.opacity.animation(.easeIn(duration: 0.2).delay(0.25)))
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        if model.phase == .won {
            ResultOverlay(mood: .win, title: "You Won!", subtitle: winSubtitle,
                          details: model.daily != nil
                            ? [("Time", model.finalTime.clockString), ("Moves", "\(model.state.moveCount)"),
                               ("Streak", "🔥 \(DailyStore.shared.streak(.solitaire))")]
                            : [("Score", "\(model.finalScore)"),
                               ("Time", model.finalTime.clockString),
                               ("Moves", "\(model.state.moveCount)")],
                          tint: accent) {
                if model.daily != nil {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                } else {
                    Button("Play Again") { model.newGame() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                    let other: Solitaire.DrawMode = model.drawMode == .draw1 ? .draw3 : .draw1
                    Button("Try \(other.title)") { model.newGame(other) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity)
        } else if model.showStuck {
            ResultOverlay(mood: .loss, title: "No Moves Left",
                          subtitle: "There are no useful moves remaining. Undo a few moves or start over.",
                          details: [("Score", "\(model.state.score)"), ("Moves", "\(model.state.moveCount)")],
                          tint: accent) {
                Button(model.daily != nil ? "Restart Deal" : "New Game") { model.newGame() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                HStack(spacing: 10) {
                    if model.canUndo {
                        Button("Undo") {
                            model.dismissStuck()
                            withAnimation(SolitaireModel.cardAnimation) { model.undo() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Keep Looking") { model.dismissStuck() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity)
        }
    }

    private var winSubtitle: String {
        var parts: [String] = []
        if model.isNewBest { parts.append("New best score!") }
        if model.timeBonus > 0 { parts.append("Includes a \(model.timeBonus) point time bonus.") }
        return parts.isEmpty ? "\(model.drawMode.title) solitaire cleared." : parts.joined(separator: " ")
    }

    static let rules = HowToPlay(
        summary: "Move every card onto the four foundations, building each suit up from Ace to King.",
        sections: [
            .init(title: "The Table", symbol: "rectangle.split.3x1", points: [
                "Seven columns are dealt with the top card face up. The rest of the deck is the stock.",
                "Tap the stock to turn over one card (Draw 1) or three (Draw 3). Only the top waste card can be played.",
                "When the stock runs out, tap it again to turn the waste back over as many times as you like.",
            ]),
            .init(title: "Moving Cards", symbol: "hand.draw", points: [
                "In the columns, build down in alternating colors: a red 6 on a black 7.",
                "Move a face-up run of cards together. Only a King, or a run led by a King, can fill an empty column.",
                "Tap a card to send it to the best spot, or drag it exactly where you want it.",
                "Revealing a hidden card turns it face up automatically.",
            ]),
            .init(title: "Scoring", symbol: "star", points: [
                "Waste to column +5, any card to a foundation +10, revealing a card +5.",
                "Taking a card back off a foundation −15. Turning the waste over −100 (Draw 1) or −20 (Draw 3).",
                "Win fast for a time bonus. Deals are checked by a solver so they can be won.",
            ]),
            .init(title: "Help", symbol: "lightbulb", points: [
                "Hint highlights a useful move. Undo takes back as many moves as you need.",
                "Once every card is face up, Auto-Complete finishes the game for you.",
            ]),
        ]
    )
}
