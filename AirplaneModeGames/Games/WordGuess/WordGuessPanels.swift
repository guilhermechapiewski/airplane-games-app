import SwiftUI
import GameLogic

/// Pass & Play: enter the two players' names.
struct WordGuessNamesCard: View {
    let accent: Color
    let onStart: (String, String) -> Void
    @State private var first: String
    @State private var second: String
    @FocusState private var focus: Int?

    init(names: [String], accent: Color, onStart: @escaping (String, String) -> Void) {
        self.accent = accent
        self.onStart = onStart
        _first = State(initialValue: names.first ?? "")
        _second = State(initialValue: names.count > 1 ? names[1] : "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(accent)
            Text("Pass & Play")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Take turns choosing a secret word for each other. Solve it in fewer guesses to score more points.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                nameField("Player 1", text: $first, tag: 0)
                nameField("Player 2", text: $second, tag: 1)
            }
            Button("Start Match") { onStart(first, second) }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("startMatch")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func nameField(_ placeholder: String, text: Binding<String>, tag: Int) -> some View {
        TextField(placeholder, text: text)
            .textContentType(.name)
            .submitLabel(tag == 0 ? .next : .done)
            .focused($focus, equals: tag)
            .onSubmit { focus = tag == 0 ? 1 : nil }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("\(placeholder) name")
    }
}

/// Pass & Play: the setter secretly types a word.
struct WordGuessSecretCard: View {
    let match: WordGuessMatch
    let accent: Color
    let onLock: (String) -> Void
    @State private var word = ""
    @FocusState private var focused: Bool

    private var problem: String? { WordGuessModel.secretProblem(word) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(accent)
            Text("\(match.setterName), pick a word")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text("Round \(match.round). Make sure \(match.guesserName) isn't looking!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("Secret 5-letter word", text: $word)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if problem == nil { onLock(word) } }
                .onChange(of: word) { _, new in
                    let filtered = String(new.filter { $0.isASCII && $0.isLetter }.prefix(WordGuess.wordLength))
                    if filtered != new { word = filtered }
                }
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("secretField")
            HStack(spacing: 8) {
                ForEach(0..<WordGuess.wordLength, id: \.self) { i in
                    Circle()
                        .fill(i < word.count ? accent : Theme.hairline)
                        .frame(width: 10, height: 10)
                }
            }
            .accessibilityHidden(true)
            Text(word.count == WordGuess.wordLength ? (problem ?? "Looks good!") : " ")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(problem == nil ? accent : .red)
                .accessibilityHidden(word.count < WordGuess.wordLength)
            Button("Lock It In") { onLock(word) }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .disabled(problem != nil)
                .opacity(problem == nil ? 1 : 0.5)
                .accessibilityIdentifier("lockSecret")
            Button("Pick a random word for me") {
                var rng = SystemRandomNumberGenerator()
                onLock(WordLists.randomAnswer(using: &rng))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(accent)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { focused = true }
    }
}

/// In-game options: hard mode, colors, and the guess distribution.
struct WordGuessOptionsSheet: View {
    @Bindable var model: WordGuessModel
    @Binding var highContrast: Bool
    private var palette: WordGuessPalette { WordGuessPalette(highContrast: highContrast) }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hard Mode", isOn: $model.hardModePreference)
                        .accessibilityIdentifier("hardModeToggle")
                } footer: {
                    Text(model.state.guesses.isEmpty || model.state.isOver
                         ? "Any revealed hints must be used in later guesses."
                         : "Any revealed hints must be used in later guesses. Takes effect from your next game.")
                }
                Section {
                    Toggle("High Contrast Colors", isOn: $highContrast)
                    HStack(spacing: 10) {
                        sample("A", .correct, "Correct")
                        sample("B", .present, "Wrong spot")
                        sample("C", .absent, "Not in word")
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Uses orange and blue, easier to tell apart for color vision differences.")
                }
                Section("Guess Distribution · vs. Computer") {
                    GuessDistributionChart(distribution: model.distribution, highlight: nil, accent: GameID.wordGuess.accent)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func sample(_ letter: String, _ state: WordGuess.LetterState, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(letter)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(palette.fill(state), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) color sample")
    }
}
