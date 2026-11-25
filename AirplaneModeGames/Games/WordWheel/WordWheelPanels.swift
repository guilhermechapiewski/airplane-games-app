import SwiftUI
import GameLogic

// MARK: - Progress

/// Rank, points and a bar that climbs through the rank markers.
struct WordWheelProgress: View {
    let model: WordWheelModel
    let onShowRanks: () -> Void

    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let rank = model.rank
        let next = rank.next
        Button(action: onShowRanks) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rank.title)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(WordWheelPalette.ink)
                        .contentTransition(.interpolate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                    Text(next.map { "\(model.points(toReach: $0) - model.score) to \($0.title)" } ?? "Top rank!")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("\(model.score) pts")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                RankBar(model: model, differentiateWithoutColor: differentiateWithoutColor)
                    .frame(height: 22)
                HStack {
                    Text("Words: \(model.foundAnswerCount) / \(model.answerCount)")
                        .monospacedDigit()
                    Spacer()
                    if let best = model.bestScore {
                        Text("Best \(best) pts").monospacedDigit()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank: \(rank.title), \(model.score) points")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows all ranks")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("wordWheelProgress")
    }

    private var accessibilityValue: String {
        let words = "\(model.foundAnswerCount) of \(model.answerCount) words found"
        guard let next = model.rank.next else { return "Top rank. \(words)" }
        return "\(model.points(toReach: next) - model.score) points to \(next.title). \(words)"
    }
}

/// The bar runs from 0 to the top rank's threshold; each rank is a marker on it. Reached markers
/// are filled and checked, so progress reads without color.
private struct RankBar: View {
    let model: WordWheelModel
    let differentiateWithoutColor: Bool

    var body: some View {
        GeometryReader { geo in
            let ranks = WordWheel.Rank.allCases
            let top = max(1, model.points(toReach: .genius))
            let progress = min(1, Double(model.score) / Double(top))
            let w = geo.size.width
            let marker: CGFloat = 18
            let inset = marker / 2
            let track = w - marker
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well).frame(height: 8).padding(.horizontal, inset)
                Capsule()
                    .fill(LinearGradient(colors: WordWheelPalette.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, track * progress), height: 8)
                    .padding(.leading, inset)
                ForEach(ranks, id: \.self) { rank in
                    let reached = model.score >= model.points(toReach: rank)
                    let x = inset + track * min(1, Double(model.points(toReach: rank)) / Double(top))
                    ZStack {
                        Circle().fill(reached ? WordWheelPalette.accent : Theme.surface)
                        Circle().strokeBorder(reached ? WordWheelPalette.accent : Theme.hairline, lineWidth: 2)
                        if reached {
                            Image(systemName: rank == model.rank ? "star.fill" : "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: rank == model.rank ? marker : marker - 4, height: rank == model.rank ? marker : marker - 4)
                    .position(x: x, y: geo.size.height / 2)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.score)
        }
        .accessibilityHidden(true)
    }
}

/// Every rank and the points it takes on this wheel.
struct WordWheelRanksSheet: View {
    let model: WordWheelModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WordWheel.Rank.allCases.reversed(), id: \.self) { rank in
                        let needed = model.points(toReach: rank)
                        let reached = model.score >= needed
                        HStack(spacing: 12) {
                            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(reached ? WordWheelPalette.ink : .secondary)
                                .font(.title3)
                            Text(rank.title)
                                .font(.headline.weight(rank == model.rank ? .heavy : .semibold))
                            if rank == model.rank {
                                Text("You")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(WordWheelPalette.accent.opacity(0.18), in: Capsule())
                                    .foregroundStyle(WordWheelPalette.ink)
                            }
                            Spacer()
                            Text("\(needed) pts").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(reached ? "reached" : "not reached")
                    }
                } footer: {
                    Text("This wheel is worth \(model.maxPoints) points in all. Reach Great to win the wheel.")
                }
            }
            .navigationTitle("Ranks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Current word

/// The word being spelled, with the center letter picked out, and feedback after Enter.
struct WordWheelEntry: View {
    let model: WordWheelModel
    let puzzle: WordWheel.Puzzle
    let input: String

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ZStack {
            if let message = model.message {
                MessageBadge(message: message)
                    .id(message.token)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                word
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: model.shakeToken) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let amp: CGFloat = reduceMotion ? 0 : 1
            KeyframeTrack {
                LinearKeyframe(-10 * amp, duration: 0.05)
                LinearKeyframe(9 * amp, duration: 0.06)
                LinearKeyframe(-6 * amp, duration: 0.06)
                LinearKeyframe(4 * amp, duration: 0.06)
                LinearKeyframe(0, duration: 0.06)
            }
        }
    }

    @ViewBuilder private var word: some View {
        if input.isEmpty {
            Text(model.canPlay ? "Tap letters to spell a word" : " ")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("currentWord")
                .accessibilityLabel("Current word")
                .accessibilityValue("empty")
        } else {
            styled
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("currentWord")
                .accessibilityLabel("Current word")
                .accessibilityValue(input.uppercased().map(String.init).joined(separator: " "))
        }
    }

    private var styled: Text {
        input.reduce(Text(verbatim: "")) { text, ch in
            let isCenter = ch == puzzle.centerLetter
            var letter = Text(String(ch).uppercased()).foregroundColor(isCenter ? WordWheelPalette.ink : .primary)
            if isCenter && differentiateWithoutColor { letter = letter.underline() }
            return text + letter
        }
    }
}

private struct MessageBadge: View {
    let message: WordWheelModel.Message

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(message.text)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(background, in: Capsule())
        .accessibilityHidden(true)   // announced instead
        .accessibilityIdentifier("entryMessage")
    }

    private var symbol: String? {
        switch message.kind {
        case .pangram: "sparkles"
        case .rank: "rosette"
        case .bonus: "plus.circle.fill"
        case .good: "checkmark.circle.fill"
        case .problem: "xmark.circle.fill"
        }
    }

    private var foreground: Color {
        switch message.kind {
        case .problem: Color(light: .white, dark: .black)
        default: .white
        }
    }

    private var background: AnyShapeStyle {
        switch message.kind {
        case .problem: AnyShapeStyle(Color(light: Color(hex: 0x1D2230), dark: Color(hex: 0xF1F3F8)))
        case .pangram, .rank: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE89A1C), Color(hex: 0xD9566B)],
                                                          startPoint: .leading, endPoint: .trailing))
        default: AnyShapeStyle(WordWheelPalette.accent)
        }
    }
}

// MARK: - Found words

/// Found words: a one-line summary that expands to the full alphabetical list (and, once the wheel
/// is finished, the answers that were missed).
struct WordWheelWordList: View {
    let model: WordWheelModel
    let state: WordWheel.State
    @Binding var expanded: Bool
    /// Side-by-side layouts keep the list open.
    var alwaysExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if alwaysExpanded {
                Label(summaryTitle, systemImage: "list.bullet")
                    .font(.headline)
                    .foregroundStyle(WordWheelPalette.ink)
                    .accessibilityIdentifier("foundCount")
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { expanded.toggle() }
                } label: {
                    summaryRow
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityLabel(summaryTitle)
                .accessibilityValue(expanded ? "expanded" : (recent.isEmpty ? "" : "Latest: \(recent.prefix(3).joined(separator: ", "))"))
                .accessibilityHint(expanded ? "Hides the list" : "Shows all found words")
                .accessibilityIdentifier("foundCount")
            }
            if expanded || alwaysExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if state.found.isEmpty && !state.isFinished {
                            Text("Words you find appear here, A to Z.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        section(nil, words: state.foundAnswers.sorted(), style: .found)
                        if !state.bonusWords.isEmpty {
                            section("Bonus words · \(state.bonusWords.count)", words: state.bonusWords.sorted(), style: .bonus)
                        }
                        if state.isFinished, !state.missedAnswers.isEmpty {
                            section("Missed · \(state.missedAnswers.count)", words: state.missedAnswers, style: .missed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var summaryTitle: String {
        let n = state.found.count
        return n == 0 ? "No words yet" : "\(n) \(n == 1 ? "word" : "words") found"
    }

    private var recent: [String] { state.found.reversed().map { $0.capitalized } }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            Text(summaryTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WordWheelPalette.ink)
                .layoutPriority(1)
            if !expanded {
                Text(recent.joined(separator: "  "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    enum WordStyle { case found, bonus, missed }

    @ViewBuilder
    private func section(_ title: String?, words: [String], style: WordStyle) -> some View {
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(words, id: \.self) { word in
                        WordChip(word: word, isPangram: model.puzzle?.isPangram(word) == true,
                                 isLatest: word == model.lastFound, style: style)
                    }
                }
            }
        }
    }
}

private struct WordChip: View {
    let word: String
    let isPangram: Bool
    let isLatest: Bool
    let style: WordWheelWordList.WordStyle

    var body: some View {
        HStack(spacing: 4) {
            if isPangram {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WordWheelPalette.gold)
            }
            Text(word.capitalized)
                .font(.subheadline.weight(isPangram ? .heavy : .semibold))
                .foregroundStyle(style == .missed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if style == .bonus {
                Text("+").font(.caption.weight(.heavy)).foregroundStyle(WordWheelPalette.ink)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: Capsule())
        .overlay {
            if style == .missed {
                Capsule().strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else if isLatest {
                Capsule().strokeBorder(WordWheelPalette.accent, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word)
        .accessibilityValue([isPangram ? "pangram" : nil, style == .bonus ? "bonus word" : nil,
                             style == .missed ? "missed" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier(style == .missed ? "missed.\(word)" : "found.\(word)")
    }

    private var background: Color {
        switch style {
        case .missed: .clear
        case .found, .bonus: isPangram ? WordWheelPalette.gold.opacity(0.18) : Theme.well
        }
    }
}
