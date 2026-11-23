import SwiftUI
import GameLogic

struct SudokuView: View {
    @State private var model = SudokuModel()
    @FocusState private var focused: Bool
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > size.height * 1.2 && size.width >= 640 {
                wideLayout(size)
            } else {
                tallLayout(size)
            }
        }
        .overlay { winOverlay }
        .gameChrome(.sudoku, rules: Self.rules, stats: StatsVariant.difficulties(),
                    newGame: Difficulty.allCases.map { level in
                        NewGameOption(title: level.title, systemImage: Self.symbol(for: level)) {
                            model.newGame(level)
                        }
                    },
                    onActiveChange: model.setActive,
                    freshStart: { model.newGame(model.difficulty) })
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { model.moveSelection(.up); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(.down); return .handled }
        .onKeyPress(.leftArrow) { model.moveSelection(.left); return .handled }
        .onKeyPress(.rightArrow) { model.moveSelection(.right); return .handled }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in model.erase(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "0123456789nNhH ")) { press in
            switch press.characters {
            case "0", " ": model.erase()
            case "n", "N": model.toggleNotesMode()
            case "h", "H": model.hint()
            default:
                guard let digit = Int(press.characters) else { return .ignored }
                model.input(digit)
            }
            return .handled
        }
    }

    // MARK: Layouts

    /// Phones and iPad portrait: header, board, tools, a single-row number pad.
    private func tallLayout(_ size: CGSize) -> some View {
        let compact = size.height < 640
        // Header, toolbar, spacing and padding take roughly this much height.
        let reserved: CGFloat = compact ? 180 : 214
        // The board is as wide as it can be (capped on iPad); the number pad gets
        // whatever height is left over, then the board shrinks if even that is too tall.
        let widest = min(size.width - 32, 860)
        let keyHeight = compact ? 46 : min(78, max(46, size.height - widest - reserved))
        let column = max(240, min(widest, size.height - reserved - keyHeight))
        return VStack(spacing: compact ? 10 : 16) {
            header
            boardArea
            controls(spacing: compact ? 10 : 16) {
                SudokuToolbar(model: model)
                SudokuNumberPad(model: model, columns: 9, keyHeight: keyHeight)
            }
        }
        .frame(maxWidth: column)
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 8 : 14)
        .frame(maxWidth: .infinity)
    }

    /// Landscape iPad (and large landscape phones): board on the left, controls beside it.
    private func wideLayout(_ size: CGSize) -> some View {
        let panel = min(340, size.width * 0.34)
        let side = floor(max(200, min(size.height - 32, size.width - panel - 76)))
        // Header, toolbar and spacing take ~190pt; the 3×3 pad gets the rest.
        let keyHeight = min(84, max(40, (side - 190) / 3))
        return HStack(spacing: 28) {
            boardArea
                .frame(width: side, height: side)
            VStack(spacing: 18) {
                header
                Spacer(minLength: 0)
                controls(spacing: 18) {
                    SudokuToolbar(model: model)
                    SudokuNumberPad(model: model, columns: 3, keyHeight: keyHeight)
                }
            }
            .frame(width: panel, height: side)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardArea: some View {
        GeometryReader { geo in
            let side = floor(min(geo.size.width, geo.size.height))
            SudokuBoardView(model: model, side: side, reduceMotion: reduceMotion)
                .overlay { boardOverlay }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            StatPill(title: "Level", value: model.difficulty.title, tint: SudokuPalette.player)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatPill(title: "Time", value: model.clock.elapsed(at: context.date).clockString)
            }
            .accessibilityIdentifier("sudoku.time")
            Spacer(minLength: 0)
            Button { model.togglePause() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(Theme.surface, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            .disabled(model.game == nil || model.isSolved)
            .accessibilityLabel(model.isPaused ? "Resume" : "Pause")
            .accessibilityIdentifier("sudoku.pause")
        }
    }

    /// The tools and number pad, replaced by the hint's explanation while one is shown.
    private func controls<Content: View>(spacing: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: spacing) { content() }
            .opacity(model.hintPreview == nil ? 1 : 0)
            .allowsHitTesting(model.hintPreview == nil)
            .overlay(alignment: .bottom) {
                if let hint = model.hintPreview {
                    HintCard(title: hint.title, explanation: hint.explanation,
                             onAnswer: { model.showHintAnswer() }, onClose: { model.dismissHint() })
                }
            }
    }

    // MARK: Overlays

    @ViewBuilder private var boardOverlay: some View {
        if model.isPaused {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(SudokuPalette.accent)
                        Text("Paused").font(.title2.weight(.bold))
                        Text(model.clock.elapsed().clockString)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Resume") { model.togglePause() }
                            .buttonStyle(PrimaryButtonStyle(color: SudokuPalette.player))
                    }
                }
                .transition(.opacity)
        } else if model.showSpinner {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Creating a \(model.difficulty.title.lowercased()) puzzle…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var winOverlay: some View {
        if model.showWin, let game = model.game {
            let time = model.clock.elapsed()
            ResultOverlay(
                mood: .win,
                title: "Solved!",
                subtitle: model.isNewBest ? "New best \(model.difficulty.title.lowercased()) time!"
                    : "\(model.difficulty.title) puzzle complete.",
                details: [
                    ("Time", time.clockString),
                    ("Best", (model.bestTime ?? time).clockString),
                    ("Hints", "\(game.hintsUsed)"),
                ],
                tint: SudokuPalette.player
            ) {
                Button("Play Again") { model.newGame(model.difficulty) }
                    .buttonStyle(PrimaryButtonStyle(color: SudokuPalette.player))
                Menu {
                    ForEach(Difficulty.allCases) { level in
                        Button { model.newGame(level) } label: {
                            Label(level.title, systemImage: Self.symbol(for: level))
                        }
                    }
                } label: {
                    Text("Change Difficulty")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.well, in: Capsule())
                }
            }
            .transition(.opacity)
        }
    }

    private static func symbol(for level: Difficulty) -> String {
        switch level {
        case .easy: "circle"
        case .medium: "circle.lefthalf.filled"
        case .hard: "circle.fill"
        case .expert: "flame.fill"
        }
    }

    static let rules = HowToPlay(
        summary: "Fill the grid so every row, column and 3×3 box contains the numbers 1 to 9 exactly once.",
        sections: [
            .init(title: "Playing", symbol: "hand.tap", points: [
                "Tap a cell, then tap a number to place it.",
                "Dark numbers are given and can't be changed; yours appear in blue.",
                "Each puzzle has exactly one solution — no guessing needed.",
            ]),
            .init(title: "Notes", symbol: "pencil", points: [
                "Turn on Notes to jot small candidate numbers in a cell.",
                "Placing a number clears it from notes in the same row, column and box.",
            ]),
            .init(title: "Help", symbol: "lightbulb", points: [
                "Repeated numbers in a row, column or box turn red.",
                "Hint explains the next square you can work out, and why. Tap Show Answer to fill it in.",
                "Undo steps back through every move. The timer pauses when you leave.",
                "With a keyboard: 1–9 to enter, arrows to move, Delete to erase, N for notes.",
            ]),
            .init(title: "Levels", symbol: "chart.bar", points: [
                "Easy: every step has only one possible number.",
                "Medium: look for the only spot left for a number.",
                "Hard: needs pointing numbers and pairs.",
                "Expert: needs X-Wings, XY-Wings and similar patterns.",
            ]),
        ]
    )
}
