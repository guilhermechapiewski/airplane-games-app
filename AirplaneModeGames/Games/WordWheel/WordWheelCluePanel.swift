import SwiftUI
import GameLogic

/// A clue for an unfound answer: what it starts with, its letter pattern, and how many words of
/// each length are left. Sits above the current word so the wheel stays usable.
struct WordWheelCluePanel: View {
    let model: WordWheelModel
    let clue: WordWheel.Clue

    private static let ink = Color(light: Color(hex: 0xA86A00), dark: HintCard.amber)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(HintCard.amber)
                    .accessibilityHidden(true)
                Text(clue.title)
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("clueTitle")
                Spacer(minLength: 0)
                Button { model.closeClue() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.well, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close clue")
                .accessibilityIdentifier("clueClose")
            }
            HStack(spacing: 10) {
                pattern
                Spacer(minLength: 0)
                Button { model.hint() } label: {
                    Text(clue.canRevealMore ? "More" : "Another Word")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HintCard.amber.opacity(0.18), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(clue.canRevealMore ? "Reveals another letter" : "Gives a clue for a different word")
                .accessibilityIdentifier("clueMore")
            }
            lengths
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HintCard.amber.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cluePanel")
    }

    private var pattern: some View {
        HStack(spacing: 3) {
            ForEach(Array(clue.pattern.enumerated()), id: \.offset) { _, letter in
                Text(letter.map { String($0).uppercased() } ?? " ")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(letter == model.puzzle?.centerLetter ? WordWheelPalette.ink : .primary)
                    .frame(width: 22, height: 26)
                    .background(letter == nil ? Theme.well : HintCard.amber.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern")
        .accessibilityValue(clue.spokenPattern)
        .accessibilityIdentifier("cluePattern")
    }

    private var lengths: some View {
        let left = model.answersLeftByLength
        return VStack(alignment: .leading, spacing: 4) {
            Text("Words left by length")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(left, id: \.length) { entry in
                    (Text("\(entry.length)").foregroundStyle(.secondary) + Text(":\u{2009}") .foregroundStyle(.secondary)
                        + Text("\(entry.count)").fontWeight(.bold))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .background(Theme.well, in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words left by length: " + left.map { "\($0.count) with \($0.length) letters" }.joined(separator: ", "))
            .accessibilityIdentifier("wordsLeftByLength")
    }
}
