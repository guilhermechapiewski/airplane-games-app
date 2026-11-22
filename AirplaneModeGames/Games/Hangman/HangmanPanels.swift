import SwiftUI
import GameLogic

/// Pass & Play: a friend secretly types a word or phrase and an optional hint.
struct HangmanSecretCard: View {
    let accent: Color
    let onLock: (String, String) -> Void
    @State private var phrase = ""
    @State private var hint = ""
    @State private var reveal = false
    @FocusState private var focus: Int?

    private var problem: Hangman.PhraseProblem? { Hangman.problem(with: phrase) }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(accent)
            Text("Choose a secret")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Type a word or short phrase while the guesser looks away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Group {
                    if reveal {
                        TextField("Word or phrase", text: $phrase)
                    } else {
                        SecureField("Word or phrase", text: $phrase)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // Not a password: keep AutoFill and "Save Password" prompts away.
                .textContentType(.oneTimeCode)
                .focused($focus, equals: 0)
                .submitLabel(.next)
                .onSubmit { focus = 1 }
                .accessibilityIdentifier("secretField")
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(reveal ? "Hide secret" : "Show secret")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField("Hint (optional)", text: $hint)
                .focused($focus, equals: 1)
                .submitLabel(.done)
                .onChange(of: hint) { _, new in if new.count > 40 { hint = String(new.prefix(40)) } }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("hintField")

            Text(phrase.isEmpty ? " " : (problem?.message ?? "Looks good!"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(problem == nil ? accent : .red)

            Button("Lock It In") { onLock(phrase, hint) }
                .buttonStyle(PrimaryButtonStyle(color: accent))
                .disabled(problem != nil)
                .opacity(problem == nil ? 1 : 0.5)
                .accessibilityIdentifier("lockSecret")
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { focus = 0 }
    }
}

/// Category picker for computer games.
struct HangmanCategorySheet: View {
    let current: String?
    let accent: Color
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    cell(id: nil, title: "Random", symbol: "shuffle")
                    ForEach(WordCategory.all) { c in cell(id: c.id, title: c.title, symbol: c.symbol) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func cell(id: String?, title: String, symbol: String) -> some View {
        let selected = id == current
        return Button { onPick(id) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 26)
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.footnote.weight(.bold)) }
            }
            .foregroundStyle(selected ? .white : accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(selected ? accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
