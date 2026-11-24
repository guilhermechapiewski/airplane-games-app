import SwiftUI
import GameLogic

struct FreeCellView: View {
    @State private var model = FreeCellModel()
    @State private var askDealNumber = false
    @State private var dealNumberText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let accent = GameID.freeCell.accent
    /// The accent for text and icons: the lighter gradient stop reads better on dark surfaces.
    private let accentInk = Color(light: GameID.freeCell.colors[1], dark: GameID.freeCell.colors[0])
    private var maxBoardWidth: CGFloat { sizeClass == .regular ? 980 : .infinity }

    var body: some View {
        VStack(spacing: sizeClass == .regular ? 18 : 10) {
            header
            FreeCellTable(model: model, showsCascade: showsCascade)
                .frame(maxWidth: maxBoardWidth, maxHeight: .infinity)
                .overlay(alignment: .bottom) { autoCompleteButton }
                .overlay { preparingBadge }
                .overlay(alignment: .top) { messageBanner }
            controls
        }
        .padding(.horizontal, sizeClass == .regular ? 24 : 6)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(FreeCellFelt().ignoresSafeArea())
        .overlay { overlay }
        .gameChrome(.freeCell, rules: Self.rules,
                    stats: [StatsVariant(key: nil, title: "Deals", showsTime: true)],
                    newGame: [
                        NewGameOption(title: "New Deal", systemImage: "shuffle") { model.newGame() },
                        NewGameOption(title: "Restart This Deal", systemImage: "arrow.counterclockwise") {
                            model.restartDeal()
                        },
                        NewGameOption(title: "Choose Deal Number…", systemImage: "number") { chooseDeal() },
                    ],
                    onActiveChange: model.setActive,
                    freshStart: { model.newGame() })
        .onAppear {
            model.reduceMotion = reduceMotion
            model.start()
        }
        .onChange(of: reduceMotion) { _, value in model.reduceMotion = value }
        .animation(.easeOut(duration: 0.25), value: model.showStuck)
        .animation(.easeOut(duration: 0.25), value: model.phase)
        .alert("Play a Deal", isPresented: $askDealNumber) {
            TextField("1–\(FreeCell.maxDeal)", text: $dealNumberText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("dealNumberField")
            Button("Deal") {
                if let n = Int(dealNumberText.filter(\.isNumber)), (1...FreeCell.maxDeal).contains(n) {
                    model.newGame(number: n)
                } else {
                    model.show("Deal numbers go from 1 to \(FreeCell.maxDeal).")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a deal number to play it (or share it with a friend).")
        }
    }

    private var showsCascade: Bool {
        !reduceMotion && (model.phase == .celebrating || model.phase == .won) && model.state.isWon
    }

    private func chooseDeal() {
        dealNumberText = ""
        askDealNumber = true
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 8) {
            StatPill(title: "Deal", value: model.phase == .preparing ? "–" : "#\(model.state.deal)", tint: accentInk)
                .accessibilityIdentifier("dealNumber")
            StatPill(title: "Moves", value: "\(model.state.moveCount)")
                .accessibilityIdentifier("movesCount")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatPill(title: "Time", value: model.clock.elapsed(at: context.date).clockString)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: maxBoardWidth)
        .animation(.snappy, value: model.state.moveCount)
    }

    private var controls: some View {
        HStack(spacing: sizeClass == .regular ? 28 : 20) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                withAnimation(FreeCellModel.cardAnimation) { model.undo() }
            }
            .disabled(!model.canUndo)
            ToolButton(title: "Hint", systemImage: model.isThinking ? "ellipsis" : "lightbulb",
                       isActive: model.hint != nil || model.isThinking, tint: hintTint) {
                model.showHint()
            }
            .disabled(!model.isInteractive)
            .accessibilityValue(model.isThinking ? "Thinking" : "")
            ToolButton(title: "Auto", systemImage: model.autoMove ? "wand.and.stars" : "wand.and.stars.inverse",
                       isActive: model.autoMove, tint: accentInk) {
                model.setAutoMove(!model.autoMove)
            }
            .accessibilityLabel("Auto-Move")
            .accessibilityValue(model.autoMove ? "On" : "Off")
            .accessibilityHint("Plays cards that are no longer needed on the table to the foundations for you.")
            .accessibilityIdentifier("autoMoveToggle")
            Menu {
                Button { model.newGame() } label: { Label("New Deal", systemImage: "shuffle") }
                Button { model.restartDeal() } label: { Label("Restart This Deal", systemImage: "arrow.counterclockwise") }
                    .disabled(!model.canRestart)
                Button { chooseDeal() } label: { Label("Choose Deal Number…", systemImage: "number") }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 40)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.primary)
                    Text("New")
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

    /// The hint yellow reads poorly on the light material; use a deeper amber there.
    private var hintTint: Color { Color(light: Color(hex: 0xC98A00), dark: SolitairePalette.hint) }

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
                Text("Finding a winnable deal…").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.3), in: Capsule())
            .transition(.opacity.animation(.easeIn(duration: 0.2).delay(0.25)))
        }
    }

    @ViewBuilder private var messageBanner: some View {
        if let message = model.message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("freeCellMessage")
                .zIndex(4000)
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        if model.phase == .won {
            ResultOverlay(mood: .win, title: "You Won!",
                          subtitle: model.isNewBest ? "New best time on FreeCell!" : "Deal #\(model.state.deal) cleared.",
                          details: [("Time", model.finalTime.clockString),
                                    ("Moves", "\(model.state.moveCount)"),
                                    ("Streak", "\(model.winStreak)")],
                          tint: accent) {
                Button("Play Again") { model.newGame() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                Button("Back to Games") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        } else if model.showStuck {
            ResultOverlay(mood: .loss, title: "No Moves Left",
                          subtitle: "Nothing can move. Undo a few moves or start over.",
                          details: [("Moves", "\(model.state.moveCount)")],
                          tint: accent) {
                Button("Undo") {
                    model.dismissStuck()
                    withAnimation(FreeCellModel.cardAnimation) { model.undo() }
                }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                HStack(spacing: 10) {
                    Button("Restart Deal") {
                        model.dismissStuck()
                        model.restartDeal()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("New Deal") { model.newGame() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity)
        }
    }

    static let rules = HowToPlay(
        summary: "Move every card onto the four foundations, building each suit up from Ace to King. All cards are face up: almost every deal can be won with careful planning.",
        sections: [
            .init(title: "The Table", symbol: "rectangle.split.3x1", points: [
                "All 52 cards are dealt face up into eight columns.",
                "Top left are four free cells: each holds any one card while you work.",
                "Top right are the four foundations, one per suit, built up from Ace to King.",
            ]),
            .init(title: "Moving Cards", symbol: "hand.draw", points: [
                "Move the top card of a column or a free cell onto a column one rank higher in the other color: a red 6 on a black 7.",
                "Any card can go to an empty column or a free cell.",
                "Ordered runs move together when there's room: (free cells + 1) × 2 for each empty column. Moving into an empty column, that column doesn't count.",
                "Tap a card to send it to the best spot, or drag it exactly where you want it.",
            ]),
            .init(title: "Help", symbol: "lightbulb", points: [
                "Hint finds a winning line from where you are and shows its next move, or tells you when there's no way to win and suggests Undo.",
                "Auto-Move sends cards that no longer help on the table to the foundations. Turn it off with the Auto button.",
                "Undo takes back as many moves as you like. Once the columns are in order, Auto-Complete finishes for you.",
                "Every deal is numbered and checked by a solver, so it can be won. Choose a deal number to replay one.",
            ]),
            .init(title: "Tips", symbol: "graduationcap", points: [
                "Keep free cells empty: every filled cell halves how many cards you can move at once.",
                "Free the Aces and Twos early. Look for low cards buried deep and plan to dig them out.",
                "An empty column is worth more than a free cell: it doubles your moving power. Try to clear the shortest column first.",
                "Before a big move, count: with 2 free cells and 1 empty column you can move (2 + 1) × 2 = 6 cards.",
                "Avoid burying a low card under a long run you can't move again.",
            ]),
        ]
    )
}

/// The FreeCell table surface: a wine-red felt with a fine fiber texture.
struct FreeCellFelt: View {
    static let center = Color(light: Color(hex: 0x9A3350), dark: Color(hex: 0x561A2C))
    static let edge = Color(light: Color(hex: 0x5E1630), dark: Color(hex: 0x220810))

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [Self.center, Self.edge],
                               center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.8)
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 0xF4EE)
                    let count = Int(size.width * size.height / 90)
                    for i in 0..<count {
                        let x = Double(rng.next() % 10_000) / 10_000 * size.width
                        let y = Double(rng.next() % 10_000) / 10_000 * size.height
                        let r = 0.4 + Double(rng.next() % 100) / 100 * 0.6
                        let color: Color = i.isMultiple(of: 2) ? .white.opacity(0.05) : .black.opacity(0.07)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(color))
                    }
                }
                .drawingGroup()
                RadialGradient(colors: [.clear, .black.opacity(0.22)], center: .center,
                               startRadius: min(geo.size.width, geo.size.height) * 0.45,
                               endRadius: max(geo.size.width, geo.size.height) * 0.85)
            }
        }
        .accessibilityHidden(true)
    }
}
