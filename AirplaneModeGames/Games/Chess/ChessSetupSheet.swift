import SwiftUI
import GameLogic

/// Choose mode, colour and level before a game.
struct ChessSetupSheet: View {
    let model: ChessModel
    @State private var setup = ChessModel.lastSetup
    @Environment(\.dismiss) private var dismiss

    private let accent = ChessTheme.accent

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        GameBadge(game: .chess, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New Game").font(.title2.bold())
                            Text("Play the computer or a friend on this device.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        modeCard(.computer, symbol: "cpu", detail: "Five levels")
                        modeCard(.passAndPlay, symbol: "person.2.fill", detail: "Share this device")
                    }

                    if setup.mode == .computer {
                        section("Play as") {
                            HStack(spacing: 10) {
                                ForEach(ChessSetup.ColorChoice.allCases) { choice in
                                    colorCard(choice)
                                }
                            }
                        }
                        section("Level") {
                            VStack(spacing: 8) {
                                ForEach(Chess.Level.allCases) { level in
                                    levelRow(level)
                                }
                            }
                        }
                    } else {
                        section("Board") {
                            Toggle(isOn: $model.autoRotate) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rotate board each turn").font(.body.weight(.semibold))
                                    Text("The player to move always sits at the bottom.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(accent)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button {
                        model.newGame(setup)
                        dismiss()
                    } label: {
                        Text("Start Game").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                    .accessibilityIdentifier("setup.start")
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: setup.mode)
            }
            .background(Theme.background)
            .navigationTitle("Chess")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("setup.cancel")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func modeCard(_ mode: ChessSetup.Mode, symbol: String, detail: String) -> some View {
        let isOn = setup.mode == mode
        return Button {
            setup.mode = mode
            Feedback.play(.select)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isOn ? .white : accent)
                    .frame(width: 54, height: 54)
                    .background(isOn ? accent : accent.opacity(0.14), in: Circle())
                Text(mode.title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? accent : Theme.hairline, lineWidth: isOn ? 2.5 : 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("setup.mode.\(mode.rawValue)")
    }

    private func colorCard(_ choice: ChessSetup.ColorChoice) -> some View {
        let isOn = setup.colorChoice == choice
        return Button {
            setup.colorChoice = choice
            Feedback.play(.select)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch choice {
                    case .white:
                        ChessPieceView(piece: Chess.Piece(.white, .king), size: 46)
                    case .black:
                        ChessPieceView(piece: Chess.Piece(.black, .king), size: 46)
                    case .random:
                        ChessPieceView(piece: Chess.Piece(.white, .king), size: 40)
                            .offset(x: -9)
                        ChessPieceView(piece: Chess.Piece(.black, .king), size: 40)
                            .offset(x: 9)
                    }
                }
                .frame(height: 48)
                Text(choice.title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? accent : Theme.hairline, lineWidth: isOn ? 2.5 : 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Play as \(choice.title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func levelRow(_ level: Chess.Level) -> some View {
        let isOn = setup.level == level
        let record = model.record(for: level)
        return Button {
            setup.level = level
            Feedback.play(.select)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { i in
                        Capsule()
                            .fill(i <= level.rawValue ? accent : accent.opacity(0.18))
                            .frame(width: 5, height: 8 + CGFloat(i) * 3)
                    }
                }
                .frame(width: 40, height: 26, alignment: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(level.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(level.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if record.total > 0 {
                    Text("\(record.wins)W · \(record.losses)L · \(record.draws)D")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? accent : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.title), level \(level.rawValue) of 5. \(level.subtitle)."
                            + (record.total > 0 ? " Record: \(record.wins) wins, \(record.losses) losses, \(record.draws) draws." : ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
