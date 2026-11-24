import SwiftUI
import GameLogic

struct HangmanView: View {
    @State private var model = HangmanModel()
    @State private var showCategories = false
    @FocusState private var focused: Bool
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let accent = GameID.hangman.accent
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .secret:
                Spacer(minLength: 0)
                HangmanSecretCard(accent: accent) { model.setSecret(phrase: $0, hint: $1) }
                Spacer(minLength: 0)
            case .handoff:
                Spacer(minLength: 0)
                handoffCard
                Spacer(minLength: 0)
            case .playing:
                header
                BalloonScene(balloons: model.state.livesLeft, won: model.state.status == .won, reduceMotion: reduceMotion)
                    .aspectRatio(1.45, contentMode: .fit)
                    .frame(maxWidth: isRegular ? 780 : 560)
                    .layoutPriority(-1)
                if let hint = model.state.hint {
                    Label(hint, systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Hint: \(hint)")
                }
                Spacer(minLength: 0)
                PhraseView(state: model.state, accent: accent, maxTile: isRegular ? 56 : 40, reduceMotion: reduceMotion)
                    .frame(maxWidth: isRegular ? 900 : 620)
                Spacer(minLength: 0)
                bottomArea
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { resultOverlay }
        .sheet(isPresented: $showCategories) {
            HangmanCategorySheet(current: model.categoryID, accent: accent) { id in
                showCategories = false
                model.chooseCategory(id)
            }
            .presentationDetents([.medium, .large])
        }
        .gameChrome(.hangman, rules: Self.rules, stats: Self.statsVariants, newGame: newGameOptions,
                    onActiveChange: model.setActive,
                    freshStart: { model.mode == .friend ? model.newFriendGame() : model.newComputerGame() })
        .focusable(model.phase == .playing)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            guard model.phase == .playing, !press.modifiers.contains(.command),
                  press.characters.count == 1, let ch = press.characters.first, ch.isASCII, ch.isLetter else { return .ignored }
            model.guess(Character(ch.lowercased()))
            return .handled
        }
        .onAppear { focused = model.phase == .playing }
        #if DEBUG
        .task {   // `-showHint`: open the hint card (screenshots)
            if ProcessInfo.processInfo.arguments.contains("-showHint") { model.showHint() }
        }
        #endif
        .onChange(of: model.phase) { _, phase in focused = phase == .playing }
    }

    private var newGameOptions: [NewGameOption] {
        HangmanModel.difficulties.map { d in
            NewGameOption(title: "\(d.title) · vs. Computer", systemImage: Self.symbol(for: d)) { model.newComputerGame(difficulty: d) }
        } + [
            NewGameOption(title: "Choose Category…", systemImage: "square.grid.2x2") { showCategories = true },
            NewGameOption(title: "Pass & Play", systemImage: "person.2.fill") { model.newFriendGame() },
        ]
    }

    private static func symbol(for d: Difficulty) -> String {
        switch d {
        case .easy: "gauge.with.dots.needle.0percent"
        case .medium: "gauge.with.dots.needle.50percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if model.mode == .friend {
                chip("Pass & Play", systemImage: "person.2.fill")
            } else {
                Button { showCategories = true } label: {
                    chip(model.state.category ?? model.categoryTitle,
                         systemImage: WordCategory.all.first { $0.title == model.state.category }?.symbol ?? "shuffle",
                         showsChevron: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Category: \(model.state.category ?? model.categoryTitle)")
                .accessibilityHint("Choose a category")
                chip(model.difficulty.title, systemImage: Self.symbol(for: model.difficulty))
                    .accessibilityLabel("Difficulty: \(model.difficulty.title)")
            }
            Spacer(minLength: 4)
            if model.canGuess { hintButton }
            LivesView(lives: model.state.livesLeft)
        }
        .frame(maxWidth: isRegular ? 780 : 560)
    }

    private var hintButton: some View {
        Button { model.showHint() } label: {
            HStack(spacing: 4) {
                Image(systemName: model.letterHint != nil ? "lightbulb.fill" : "lightbulb")
                if model.hintsUsed > 0 {
                    Text("\(model.hintsUsed)").monospacedDigit()
                }
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color(light: Color(hex: 0xA86A00), dark: HintCard.amber))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 34, minHeight: 28)
            .background(HintCard.amber.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Hint")
        .accessibilityValue(model.hintsUsed > 0 ? "\(model.hintsUsed) used" : "")
        .accessibilityHint("Suggests a letter to try")
        .accessibilityIdentifier("hangmanHint")
    }

    private func chip(_ title: String, systemImage: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.caption2.weight(.bold)) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(accent.opacity(0.13), in: Capsule())
    }

    // MARK: Bottom

    @ViewBuilder private var bottomArea: some View {
        if model.state.isOver && !model.showResult {
            HStack(spacing: 12) {
                Button("Results") { model.reopenResult() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(model.mode == .friend ? "New Word" : "Play Again") { model.playAgain() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
            }
            .frame(height: 150)
        } else {
            HangmanKeyboard(model: model, accent: accent)
                .opacity(model.letterHint == nil ? 1 : 0)
                .allowsHitTesting(model.letterHint == nil)
                .accessibilityHidden(model.letterHint != nil)
                .overlay(alignment: .bottom) {
                    if let hint = model.letterHint {
                        HintCard(title: hint.title, explanation: hint.explanation,
                                 answerTitle: "Guess \(String(hint.letter).uppercased())",
                                 onAnswer: { model.guessHint() }, onClose: { model.dismissHint() })
                    }
                }
                .frame(maxWidth: isRegular ? 680 : 560)
        }
    }

    private var handoffCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.point.right.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(accent)
                .symbolEffect(.pulse)
            Text("Hand the phone over")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Your secret is locked in. Pass the phone to the guesser — they tap Start when ready.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Guessing") { model.beginGuessing() }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("startGuessing")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Result

    @ViewBuilder private var resultOverlay: some View {
        if model.showResult && model.state.isOver {
            let won = model.state.status == .won
            let s = StatsStore.shared.stats(for: .hangman, variant: model.statsVariant)
            ResultOverlay(mood: won ? .win : .loss,
                          title: won ? "Up, up and away!" : "Touchdown!",
                          subtitle: won ? "You solved \(model.state.phrase.uppercased())."
                                        : "The answer was \(model.state.phrase.uppercased()).",
                          details: (won ? [("Lives", "\(model.state.livesLeft)"), ("Streak", "\(s.currentStreak)")]
                                        : [("Played", "\(s.played)"), ("Won", "\(s.won)")])
                                   + (model.hintsUsed > 0 ? [("Hints", "\(model.hintsUsed)")] : []),
                          tint: accent) {
                Button(model.mode == .friend ? "New Word" : "Play Again") { model.playAgain() }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("playAgain")
                Button("View Board") { model.dismissResult() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        }
    }

    static let statsVariants: [StatsVariant] = HangmanModel.difficulties.map {
        StatsVariant(key: $0.rawValue, title: "\($0.title) · vs. Computer")
    } + [StatsVariant(key: "friend", title: "Pass & Play")]

    static let rules = HowToPlay(
        summary: "Guess the hidden word or phrase one letter at a time before the balloons drift away.",
        sections: [
            .init(title: "Guessing", symbol: "character.cursor.ibeam", points: [
                "Tap a letter. If it's in the answer, every copy is revealed.",
                "Spaces, hyphens and apostrophes are shown from the start.",
                "On iPad with a keyboard, just type letters.",
            ]),
            .init(title: "Balloons", symbol: "cloud.sun", points: [
                "You start with 6 balloons. Each wrong letter lets one float away.",
                "Lose all six and the basket lands — the answer is revealed.",
            ]),
            .init(title: "Modes", symbol: "person.2", points: [
                "vs. Computer: pick a category (or Random) and a difficulty. Hard words are short with unusual letters.",
                "Pass & Play: a friend secretly types a word or phrase and an optional hint, then hands you the phone.",
            ]),
            .init(title: "Hint", symbol: "lightbulb", points: [
                "Tap the light bulb for the best letter to try next: the one found in the most category words that still fit the board.",
                "In Pass & Play it can't know your friend's words, so it suggests the most common English letter you haven't tried.",
                "Hints never cost a balloon. The number you used is shown with your result.",
            ]),
            .init(title: "Tips", symbol: "graduationcap", points: [
                "Start with vowels and the most common consonants: E, A, O, I, then T, N, S, R.",
                "Every word needs a vowel, and Y often stands in for one in short words like SKY or GYM.",
                "Look at the shape: a short word in a phrase is often THE, AND or OF, and a word ending in _ _ G is often -ING.",
                "Once a few letters are in, say the word out loud with the blanks, and think of what fits the category.",
                "Save rare letters like J, Q, X and Z until the pattern points to them.",
            ]),
        ]
    )
}

// MARK: - Lives

private struct LivesView: View {
    let lives: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Hangman.maxLives, id: \.self) { i in
                Circle()
                    .fill(i < lives ? BalloonScene.colors[i] : Color.secondary.opacity(0.2))
                    .frame(width: 11, height: 13)
                    .scaleEffect(i < lives ? 1 : 0.75)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: lives)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lives) of \(Hangman.maxLives) balloons left")
        .accessibilityIdentifier("lives")
    }
}

// MARK: - Phrase

private struct PhraseView: View {
    let state: Hangman.State
    let accent: Color
    let maxTile: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let words = state.phrase.split(separator: " ").map(String.init)
        let longest = max(words.map(\.count).max() ?? 1, 6)
        GeometryReader { geo in
            let gap: CGFloat = 5
            let tile = min(maxTile, (geo.size.width - gap * CGFloat(longest - 1)) / CGFloat(longest))
            WrapLayout(spacing: tile * 0.7, lineSpacing: tile * 0.35) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    HStack(spacing: gap) {
                        ForEach(Array(word.enumerated()), id: \.offset) { _, ch in
                            PhraseTile(letter: ch, revealed: state.isRevealed(ch),
                                       missed: state.status == .lost && !state.guessed.contains(ch) && !Hangman.isAutoRevealed(ch),
                                       size: tile, accent: accent, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minHeight: 60, idealHeight: 120, maxHeight: maxTile * 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answer")
        .accessibilityValue(spoken)
        .accessibilityIdentifier("phrase")
    }

    private var spoken: String {
        state.phrase.split(separator: " ").map { word in
            word.map { ch in
                if ch == "-" { return "hyphen" }
                if ch == "'" { return "apostrophe" }
                return state.isRevealed(ch) ? String(ch).uppercased() : "blank"
            }.joined(separator: ", ")
        }.joined(separator: "; space; ")
    }
}

private struct PhraseTile: View {
    let letter: Character
    let revealed: Bool
    let missed: Bool
    let size: CGFloat
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        let isLetter = !Hangman.isAutoRevealed(letter)
        VStack(spacing: 3) {
            ZStack {
                if revealed {
                    Text(String(letter).uppercased())
                        .font(.system(size: size * 0.72, weight: .bold, design: .rounded))
                        .foregroundStyle(missed ? Color(hex: 0xF0703C) : .primary)
                        .minimumScaleFactor(0.5)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            Capsule()
                .fill(isLetter ? (revealed && !missed ? accent : Color.secondary.opacity(0.45)) : .clear)
                .frame(width: size, height: 3)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: revealed)
    }
}

/// Lays out word groups left-to-right, wrapping whole words onto centered lines.
private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func lines(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var result: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + spacing + size.width > width {
                result.append([])
                x = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            result[result.count - 1].append((i, size))
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        let ls = lines(subviews, width: width)
        let height = ls.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + lineSpacing * CGFloat(max(0, ls.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ls = lines(subviews, width: bounds.width)
        let total = ls.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + lineSpacing * CGFloat(max(0, ls.count - 1))
        var y = bounds.minY + max(0, (bounds.height - total) / 2)
        for line in ls {
            let lineWidth = line.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, line.count - 1))
            var x = bounds.minX + (bounds.width - lineWidth) / 2
            let h = line.map(\.1.height).max() ?? 0
            for (i, size) in line {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + lineSpacing
        }
    }
}

// MARK: - Keyboard

private struct HangmanKeyboard: View {
    let model: HangmanModel
    let accent: Color
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let unit = (geo.size.width - gap * 9) / 10
            let height = min(54, max(40, geo.size.height / 3 - gap))
            VStack(spacing: gap) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(Array(row), id: \.self) { ch in key(ch, width: unit, height: height) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 3 * 54 + 2 * 6)
    }

    private func key(_ ch: Character, width: CGFloat, height: CGFloat) -> some View {
        let state = model.keyState(ch)
        let fill: Color = switch state {
        case .unused: Color(light: Color(hex: 0xDCE0EA), dark: Color(hex: 0x464C60))
        case .hit: accent
        case .miss: Color(light: Color(hex: 0xEDEFF4), dark: Color(hex: 0x22252D))
        }
        return Button { model.guess(ch) } label: {
            Text(String(ch).uppercased())
                .font(.system(size: min(22, width * 0.62), weight: .semibold, design: .rounded))
                .foregroundStyle(state == .hit ? Color.white : state == .miss ? Color.secondary.opacity(0.5) : .primary)
                .strikethrough(state == .miss, color: .secondary.opacity(0.6))
                .frame(width: width, height: height)
                .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(state != .unused || !model.canGuess)
        .animation(.easeOut(duration: 0.2), value: state)
        .accessibilityLabel(String(ch).uppercased())
        .accessibilityValue(state == .hit ? "in the answer" : state == .miss ? "not in the answer" : "")
        .accessibilityIdentifier("key.\(ch)")
    }
}
