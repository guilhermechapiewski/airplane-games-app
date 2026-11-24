import SwiftUI
import GameLogic

struct WordGuessView: View {
    @State private var model = WordGuessModel()
    @State private var showOptions = false
    @AppStorage(WordGuessModel.highContrastKey) private var highContrast = false
    @FocusState private var boardFocused: Bool
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }
    private var palette: WordGuessPalette { WordGuessPalette(highContrast: highContrast) }
    private let accent = GameID.wordGuess.accent

    var body: some View {
        VStack(spacing: 12) {
            statusBar
            switch model.phase {
            case .names:
                Spacer(minLength: 0)
                WordGuessNamesCard(names: model.match.names, accent: accent) { model.confirmNames($0, $1) }
                Spacer(minLength: 0)
            case .secret:
                Spacer(minLength: 0)
                WordGuessSecretCard(match: model.match, accent: accent) { model.setSecret($0) }
                Spacer(minLength: 0)
            case .handoff:
                Spacer(minLength: 0)
                handoffCard
                Spacer(minLength: 0)
            case .playing, .roundOver:
                board
                bottomArea
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { toast }
        .overlay { resultOverlay }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showOptions = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Options")
                .accessibilityIdentifier("wordGuessOptions")
            }
        }
        .sheet(isPresented: $showOptions) {
            WordGuessOptionsSheet(model: model, highContrast: $highContrast)
                .presentationDetents([.medium, .large])
        }
        .gameChrome(.wordGuess, rules: Self.rules,
                    stats: [StatsVariant(key: WordGuessMode.computer.rawValue, title: WordGuessMode.computer.title),
                            StatsVariant(key: WordGuessMode.friend.rawValue, title: WordGuessMode.friend.title)],
                    newGame: [
                        NewGameOption(title: WordGuessMode.computer.title, systemImage: "cpu") { model.newComputerGame() },
                        NewGameOption(title: WordGuessMode.friend.title, systemImage: "person.2.fill") { model.newFriendMatch() },
                    ],
                    onActiveChange: model.setActive,
                    freshStart: { model.mode == .friend ? model.newFriendMatch() : model.newComputerGame() })
        .focusable(model.phase == .playing)
        .focused($boardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onAppear { boardFocused = model.phase == .playing }
        #if DEBUG
        .task {   // `-showHint`: open the hint card (screenshots)
            if ProcessInfo.processInfo.arguments.contains("-showHint") { model.showHint() }
        }
        #endif
        .onChange(of: model.phase) { _, phase in boardFocused = phase == .playing }
    }

    // MARK: Header

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label(model.statusLine, systemImage: model.mode == .computer ? "cpu" : "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if model.mode == .friend {
                ScoreChip(match: model.match, accent: accent)
            }
            if model.phase == .playing && !model.state.isOver {
                hintButton
            }
        }
        .frame(maxWidth: isRegular ? 700 : 520)
        .accessibilityElement(children: .contain)
    }

    private var hintButton: some View {
        Button { model.showHint() } label: {
            HStack(spacing: 5) {
                if model.isThinking {
                    ProgressView().controlSize(.mini).tint(HintCard.amber)
                } else {
                    Image(systemName: model.hint != nil ? "lightbulb.fill" : "lightbulb")
                }
                Text("Hint")
                if model.hintsUsed > 0 {
                    Text("\(model.hintsUsed)")
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .background(HintCard.amber, in: Capsule())
                }
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color(light: Color(hex: 0xA86A00), dark: HintCard.amber))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(HintCard.amber.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!model.canHint)
        .accessibilityLabel("Hint")
        .accessibilityValue(model.hintsUsed > 0 ? "\(model.hintsUsed) used" : "")
        .accessibilityHint("Suggests a good next guess")
        .accessibilityIdentifier("wordGuessHint")
    }

    // MARK: Board

    private var board: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let byWidth = (geo.size.width - gap * 4) / 5
            let byHeight = (geo.size.height - gap * 5) / 6
            let tile = max(20, min(byWidth, byHeight, isRegular ? 96 : 68))
            VStack(spacing: gap) {
                ForEach(0..<WordGuess.maxGuesses, id: \.self) { row in
                    rowView(row, tile: tile, gap: gap)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board")
        .accessibilityIdentifier("wordGuessBoard")
    }

    private func rowView(_ row: Int, tile: CGFloat, gap: CGFloat) -> some View {
        let state = model.state
        let submitted = row < state.guesses.count ? state.guesses[row] : nil
        let isCurrent = row == state.guesses.count && !state.isOver
        let letters: [Character] = submitted.map { Array($0.word) } ?? (isCurrent ? Array(state.current) : [])
        let isWinningRow = submitted?.isCorrect == true
        return HStack(spacing: gap) {
            ForEach(0..<WordGuess.wordLength, id: \.self) { col in
                LetterTile(letter: col < letters.count ? letters[col] : nil,
                           state: submitted?.states[col],
                           revealDelay: Double(col) * WordGuessModel.revealStep,
                           bounceTrigger: isWinningRow ? model.bounceToken : 0,
                           bounceDelay: Double(col) * 0.09,
                           size: tile, palette: palette, reduceMotion: reduceMotion)
            }
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: isCurrent ? model.shakeToken : 0) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let amp: CGFloat = reduceMotion ? 0 : 1
            KeyframeTrack {
                LinearKeyframe(-9 * amp, duration: 0.05)
                LinearKeyframe(8 * amp, duration: 0.06)
                LinearKeyframe(-6 * amp, duration: 0.06)
                LinearKeyframe(5 * amp, duration: 0.06)
                LinearKeyframe(-3 * amp, duration: 0.06)
                LinearKeyframe(0, duration: 0.06)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(row, submitted: submitted, typed: isCurrent ? state.current : nil))
        .accessibilityIdentifier("row\(row)")
    }

    private func rowLabel(_ row: Int, submitted: WordGuess.Guess?, typed: String?) -> String {
        if let submitted {
            let parts = zip(submitted.word, submitted.states).map { letter, s in
                "\(String(letter).uppercased()) \(WordGuessPalette.spoken(s))"
            }
            return "Guess \(row + 1), \(submitted.word.uppercased()): " + parts.joined(separator: ", ")
        }
        if let typed {
            return typed.isEmpty ? "Guess \(row + 1), empty" : "Guess \(row + 1), typing: " + typed.uppercased().map(String.init).joined(separator: " ")
        }
        return "Guess \(row + 1), empty"
    }

    // MARK: Bottom

    @ViewBuilder private var bottomArea: some View {
        if model.state.isOver && !model.showResult {
            HStack(spacing: 12) {
                Button("Results") { withAnimation { model.reopenResult() } }
                    .buttonStyle(SecondaryButtonStyle())
                if model.mode == .friend {
                    Button("Next Round") { model.nextRound() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                } else {
                    Button("Play Again") { model.newComputerGame() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                }
            }
            .frame(height: 170)
        } else {
            WordGuessKeyboard(keyboard: model.keyboard, palette: palette, enabled: model.canType && model.hint == nil,
                              keyHeight: isRegular ? 66 : 58,
                              onLetter: model.type, onEnter: model.submit, onDelete: model.deleteLetter)
                .opacity(model.hint == nil ? 1 : 0)
                .accessibilityHidden(model.hint != nil)
                .overlay(alignment: .bottom) {
                    if let hint = model.hint {
                        HintCard(title: hint.title, explanation: hint.explanation,
                                 answerTitle: "Type \(hint.word.uppercased())",
                                 onAnswer: { model.typeHint() }, onClose: { model.dismissHint() })
                    }
                }
                .frame(maxWidth: isRegular ? 700 : 560)
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(light: .white, dark: .black))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(light: Color(hex: 0x1D2230), dark: Color(hex: 0xF1F3F8)), in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.top, 36)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    // MARK: Pass & Play

    private var handoffCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.point.right.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(accent)
                .symbolEffect(.pulse)
            Text("Hand the phone to \(model.match.guesserName)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text("The secret word is locked in. \(model.match.guesserName), tap below when you're ready.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("I'm \(model.match.guesserName) — Start") { model.beginGuessing() }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("startGuessing")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Results

    @ViewBuilder private var resultOverlay: some View {
        if model.showResult && model.state.isOver {
            let won = model.state.status == .won
            let n = model.state.guesses.count
            let word = model.state.answer.uppercased()
            if model.mode == .computer {
                let s = StatsStore.shared.stats(for: .wordGuess, variant: model.statsVariant)
                ResultOverlay(mood: won ? .win : .loss,
                              title: won ? Self.praise[min(n, 6) - 1] : "Out of tries",
                              subtitle: won ? "You found \(word) in \(n) \(n == 1 ? "guess" : "guesses")." : "The word was \(word).",
                              details: [("Played", "\(s.played)"),
                                        ("Win %", s.played == 0 ? "–" : "\(Int((s.winRate * 100).rounded()))"),
                                        ("Streak", "\(s.currentStreak)")]
                                + hintsDetail,
                              tint: accent) {
                    GuessDistributionChart(distribution: model.distribution, highlight: won ? n : nil, accent: accent)
                        .padding(.bottom, 4)
                    Button("Play Again") { model.newComputerGame() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                        .accessibilityIdentifier("playAgain")
                    Button("View Board") { model.dismissResult() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.opacity)
            } else {
                let match = model.match
                ResultOverlay(mood: won ? .win : .loss,
                              title: won ? "\(match.guesserName) got it!" : "Stumped!",
                              subtitle: won
                                ? "\(word) in \(n) · +\(WordGuessMatch.points(forSolvingIn: n)) points"
                                : "\(match.setterName)'s word was \(word).",
                              details: [(match.names[0], "\(match.scores[0])"), (match.names[1], "\(match.scores[1])")] + hintsDetail,
                              tint: accent) {
                    Button("Next Round: \(match.guesserName) picks") { model.nextRound() }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                        .accessibilityIdentifier("nextRound")
                    Button("View Board") { model.dismissResult() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.opacity)
            }
        }
    }

    /// Hints used, when any: shown with the result.
    private var hintsDetail: [(String, String)] {
        model.hintsUsed > 0 ? [("Hints", "\(model.hintsUsed)")] : []
    }

    // MARK: Hardware keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard model.phase == .playing, !showOptions else { return .ignored }
        if press.key == .return {
            model.submit()
            return .handled
        }
        if press.key == .delete || press.key == .deleteForward {
            model.deleteLetter()
            return .handled
        }
        if press.modifiers.contains(.command) { return .ignored }
        if let ch = press.characters.first, press.characters.count == 1, ch.isASCII, ch.isLetter {
            model.type(ch)
            return .handled
        }
        return .ignored
    }

    static let praise = ["Genius!", "Brilliant!", "Splendid!", "Great job!", "Nice one!", "Phew!"]

    static let rules = HowToPlay(
        summary: "Find the secret five-letter word in six tries.",
        sections: [
            .init(title: "Guessing", symbol: "keyboard", points: [
                "Type any valid five-letter word and press Enter.",
                "After each guess the tiles flip to show how close you were.",
                "On iPad with a keyboard, just type — Return submits, Delete erases.",
            ]),
            .init(title: "Colors", symbol: "paintpalette", points: [
                "Teal: the letter is in the word and in the right spot.",
                "Apricot: the letter is in the word but in a different spot.",
                "Gray: the letter isn't in the word (or not that many times).",
                "Prefer orange and blue? Turn on High Contrast in Options.",
            ]),
            .init(title: "Modes", symbol: "person.2", points: [
                "vs. Computer: a random everyday word, as many games as you like.",
                "Pass & Play: a friend secretly types a word, then hands you the phone. Swap roles each round — solving faster scores more points.",
                "Hard Mode: any revealed hints must be used in later guesses.",
            ]),
            .init(title: "Hint", symbol: "lightbulb", points: [
                "Stuck? Tap Hint for a good next guess: a word that fits every clue so far (and Hard Mode), picked to rule out as many answers as possible.",
                "It says how many words still fit and why the guess helps. Tap Type to fill it in — you still press Enter.",
                "Hints never cost a guess. The number you used is shown with your result.",
            ]),
            .init(title: "Tips", symbol: "graduationcap", points: [
                "Open with five different common letters, like those in SLATE, CRANE or TRACE, to learn the most from your first guess.",
                "If you only have a couple of letters, a guess made of brand-new letters often teaches you more than one that just tries to fit.",
                "Watch for double letters: words like SPEED, LLAMA or ABBEY trip people up.",
                "Think about where letters like to sit: S, C and B often start words, while E, Y and K often end them.",
                "When several words differ by one letter (BILLS, FILLS, HILLS…), spend a guess that covers several of those letters at once — outside Hard Mode.",
            ]),
        ]
    )
}

// MARK: - Palette

struct WordGuessPalette {
    let highContrast: Bool

    func fill(_ state: WordGuess.LetterState) -> Color {
        switch state {
        case .correct: highContrast ? Color(hex: 0xF07A2E) : Color(hex: 0x1FA398)
        case .present: highContrast ? Color(hex: 0x3D8FE0) : Color(hex: 0xF0A45C)
        case .absent: Color(light: Color(hex: 0x8C93A3), dark: Color(hex: 0x3B404D))
        case .unknown: Color(light: Color(hex: 0xDCE0EA), dark: Color(hex: 0x30364A))
        }
    }

    func text(_ state: WordGuess.LetterState) -> Color {
        state == .unknown ? .primary : .white
    }

    /// Keyboard keys: in dark mode used letters recede and unused ones stay raised.
    func keyFill(_ state: WordGuess.LetterState) -> Color {
        switch state {
        case .absent: Color(light: Color(hex: 0x8C93A3), dark: Color(hex: 0x22252D))
        case .unknown: Color(light: Color(hex: 0xDCE0EA), dark: Color(hex: 0x464C60))
        default: fill(state)
        }
    }

    func keyText(_ state: WordGuess.LetterState) -> Color {
        state == .absent ? Color(light: .white, dark: Color.white.opacity(0.45)) : text(state)
    }

    static func spoken(_ state: WordGuess.LetterState) -> String {
        switch state {
        case .correct: "correct"
        case .present: "in the word, wrong spot"
        case .absent: "not in the word"
        case .unknown: "unused"
        }
    }
}

// MARK: - Tile

private struct LetterTile: View {
    let letter: Character?
    /// `nil` until the guess is submitted.
    let state: WordGuess.LetterState?
    let revealDelay: Double
    let bounceTrigger: Int
    let bounceDelay: Double
    let size: CGFloat
    let palette: WordGuessPalette
    let reduceMotion: Bool

    @State private var angle: Double = 0
    @State private var showsResult: Bool
    /// "Differentiate Without Color": add a shape to each result so color isn't the only signal.
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor
    @State private var pop = 0

    init(letter: Character?, state: WordGuess.LetterState?, revealDelay: Double, bounceTrigger: Int,
         bounceDelay: Double, size: CGFloat, palette: WordGuessPalette, reduceMotion: Bool) {
        self.letter = letter
        self.state = state
        self.revealDelay = revealDelay
        self.bounceTrigger = bounceTrigger
        self.bounceDelay = bounceDelay
        self.size = size
        self.palette = palette
        self.reduceMotion = reduceMotion
        _showsResult = State(initialValue: state != nil)
    }

    /// Right letter, right spot: a check. Right letter, wrong spot: arrows. Not in the word: none.
    static func symbol(_ state: WordGuess.LetterState) -> String? {
        switch state {
        case .correct: "checkmark"
        case .present: "arrow.left.arrow.right"
        default: nil
        }
    }

    var body: some View {
        let revealed = showsResult ? state : nil
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(revealed.map { palette.fill($0) } ?? Theme.surface)
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .strokeBorder(revealed != nil ? .clear : (letter == nil ? Theme.hairline : Color.secondary.opacity(0.55)),
                              lineWidth: max(1.5, size * 0.035))
            if let letter {
                Text(String(letter).uppercased())
                    .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(revealed.map { palette.text($0) } ?? .primary)
                    .minimumScaleFactor(0.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if differentiateWithoutColor, let symbol = revealed.flatMap(Self.symbol) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.2, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(size * 0.07)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: pop) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(reduceMotion ? 1 : 1.12), duration: 0.07)
                SpringKeyframe(CGFloat(1), duration: 0.12)
                LinearKeyframe(CGFloat(1), duration: 0.04) // land exactly at rest
            }
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: bounceTrigger) { view, y in
            view.offset(y: y)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(CGFloat(0), duration: bounceDelay + 0.01)
                SpringKeyframe(reduceMotion ? 0 : -size * 0.32, duration: 0.14)
                SpringKeyframe(CGFloat(0), duration: 0.3, spring: .bouncy)
                LinearKeyframe(CGFloat(0), duration: 0.04) // land exactly at rest
            }
        }
        .onChange(of: letter) { old, new in
            if new != nil && old == nil && state == nil { pop += 1 }
        }
        .task(id: state != nil) { await syncReveal() }
    }

    private func syncReveal() async {
        let target = state != nil
        guard target != showsResult else { return }
        if !target || reduceMotion {
            angle = 0
            showsResult = target
            return
        }
        let half = WordGuessModel.flipDuration / 2
        do {
            try await Task.sleep(for: .seconds(revealDelay))
            withAnimation(.easeIn(duration: half)) { angle = 90 }
            try await Task.sleep(for: .seconds(half))
            angle = -90
            showsResult = true
            withAnimation(.easeOut(duration: half)) { angle = 0 }
        } catch {
            angle = 0
            showsResult = target
        }
    }
}

// MARK: - Keyboard

private struct WordGuessKeyboard: View {
    let keyboard: [Character: WordGuess.LetterState]
    let palette: WordGuessPalette
    let enabled: Bool
    let keyHeight: CGFloat
    let onLetter: (Character) -> Void
    let onEnter: () -> Void
    let onDelete: () -> Void

    private static let rows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let unit = (geo.size.width - gap * 9) / 10
            let height = min(keyHeight, max(42, geo.size.height / 3 - gap))
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: gap) {
                        if r == 2 {
                            actionKey(title: "Enter", systemImage: nil, width: unit * 1.5 + gap / 2, height: height, action: onEnter)
                                .accessibilityIdentifier("key.enter")
                        }
                        ForEach(Array(Self.rows[r]), id: \.self) { ch in
                            letterKey(ch, width: unit, height: height)
                        }
                        if r == 2 {
                            actionKey(title: "Delete", systemImage: "delete.left", width: unit * 1.5 + gap / 2, height: height, action: onDelete)
                                .accessibilityIdentifier("key.delete")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 3 * keyHeight + 2 * 6)
    }

    private func letterKey(_ ch: Character, width: CGFloat, height: CGFloat) -> some View {
        let state = keyboard[ch] ?? .unknown
        return Button { onLetter(ch) } label: {
            Text(String(ch).uppercased())
                .font(.system(size: min(22, width * 0.62), weight: .semibold, design: .rounded))
                .foregroundStyle(palette.keyText(state))
                .frame(width: width, height: height)
                .background(palette.keyFill(state), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(String(ch).uppercased())
        .accessibilityValue(state == .unknown ? "" : WordGuessPalette.spoken(state))
        .accessibilityIdentifier("key.\(ch)")
    }

    private func actionKey(title: String, systemImage: String?, width: CGFloat, height: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                } else {
                    Text(title.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(.primary)
            .frame(width: width, height: height)
            .background(palette.keyFill(.unknown), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

// MARK: - Distribution

struct GuessDistributionChart: View {
    let distribution: [Int]
    /// 1-based guess count to highlight (the game just won), if any.
    let highlight: Int?
    let accent: Color

    var body: some View {
        let top = max(1, distribution.max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Guess Distribution")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(distribution.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 12)
                    GeometryReader { geo in
                        let fraction = CGFloat(distribution[i]) / CGFloat(top)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(highlight == i + 1 ? accent : Color.secondary.opacity(0.35))
                            .frame(width: max(22, geo.size.width * fraction))
                            .overlay(alignment: .trailing) {
                                Text("\(distribution[i])")
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.trailing, 6)
                            }
                    }
                    .frame(height: 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(i + 1) \(i == 0 ? "guess" : "guesses")")
                .accessibilityValue("\(distribution[i]) wins")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Score chip

private struct ScoreChip: View {
    let match: WordGuessMatch
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(match.names[0]).lineLimit(1)
            Text("\(match.scores[0]) – \(match.scores[1])")
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(match.names[1]).lineLimit(1)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score: \(match.names[0]) \(match.scores[0]), \(match.names[1]) \(match.scores[1])")
    }
}
