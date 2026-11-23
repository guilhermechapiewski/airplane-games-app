import SwiftUI
import GameLogic

/// Game-local colors for Sudoku.
enum SudokuPalette {
    static let accent = Color(hex: 0x5B8CFF)
    static let given = Color(light: Color(hex: 0x1C2233), dark: Color(hex: 0xECEEF5))
    static let player = Color(light: Color(hex: 0x2F57D9), dark: Color(hex: 0x8DABFF))
    static let conflict = Color(light: Color(hex: 0xE0393E), dark: Color(hex: 0xFF6B6B))
    static let note = Color(light: Color(hex: 0x6B7287), dark: Color(hex: 0x9AA1B5))

    static let selected = Color(light: Color(hex: 0x5B8CFF, opacity: 0.36), dark: Color(hex: 0x5B8CFF, opacity: 0.5))
    static let sameDigit = Color(light: Color(hex: 0x5B8CFF, opacity: 0.2), dark: Color(hex: 0x5B8CFF, opacity: 0.28))
    static let peer = Color(light: Color(hex: 0x5B8CFF, opacity: 0.075), dark: Color(hex: 0x5B8CFF, opacity: 0.11))
    static let conflictFill = Color(light: Color(hex: 0xFF4D4F, opacity: 0.16), dark: Color(hex: 0xFF4D4F, opacity: 0.24))
    static let hintArea = Color(light: Color(hex: 0xF0A500, opacity: 0.13), dark: Color(hex: 0xF0A500, opacity: 0.18))
    static let hintBlocker = Color(light: Color(hex: 0xF0A500, opacity: 0.38), dark: Color(hex: 0xF0A500, opacity: 0.45))
    static let hintTarget = Color(light: Color(hex: 0xF0A500, opacity: 0.55), dark: Color(hex: 0xF0A500, opacity: 0.6))
    static let wave = Color(light: Color(hex: 0x5B8CFF, opacity: 0.55), dark: Color(hex: 0x7EA2FF, opacity: 0.55))

    static let boxLine = Color(light: Color(hex: 0x30374D), dark: Color(hex: 0x7D869F))
    static let cellLine = Color(light: Color(hex: 0xD3D7E3), dark: Color(hex: 0x323848))
}

struct SudokuBoardView: View {
    let model: SudokuModel
    let side: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let cell = side / 9
        let game = model.game
        let highlighted = model.highlightedDigit
        let conflicts = game?.conflicts ?? []
        let selected = model.selected

        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { c in
                        let i = Sudoku.index(row: r, column: c)
                        SudokuCellView(
                            value: game?.values[i] ?? 0,
                            isGiven: game?.isGiven(i) ?? false,
                            notes: game?.notes[i] ?? 0,
                            highlight: highlight(i, selected: selected, digit: highlighted, game: game),
                            isConflict: conflicts.contains(i),
                            noteHighlight: highlighted,
                            size: cell,
                            pop: model.popCount[i],
                            wave: model.waveCount[i],
                            waveDelay: model.waveDelay[i],
                            reduceMotion: reduceMotion
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(i) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Row \(r + 1), column \(c + 1)")
                        .accessibilityValue(accessibilityValue(i, game: game, conflicts: conflicts))
                        .accessibilityAddTraits(selected == i ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(game?.isGiven(i) == true ? "" : "Swipe up or down to change the number.")
                        .accessibilityAction { model.select(i) }
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: model.adjust(i, up: true)
                            case .decrement: model.adjust(i, up: false)
                            @unknown default: break
                            }
                        }
                        .accessibilityIdentifier("sudoku.cell.\(r).\(c)")
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .background(Theme.surface)
        .overlay { GridLines().allowsHitTesting(false).accessibilityHidden(true) }
        .clipShape(RoundedRectangle(cornerRadius: max(6, side * 0.018), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(6, side * 0.018), style: .continuous)
                .strokeBorder(SudokuPalette.boxLine, lineWidth: Self.boxLineWidth(side))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sudoku board")
        .accessibilityIdentifier("sudokuBoard")
    }

    static func boxLineWidth(_ side: CGFloat) -> CGFloat { side > 500 ? 2.5 : 2 }

    private func highlight(_ i: Int, selected: Int?, digit: Int?, game: Sudoku.Game?) -> SudokuCellView.Highlight {
        if let hint = model.hintPreview {
            // While a hint is explained, show only its reasoning.
            if i == hint.cell { return .hintTarget }
            if hint.blockers.contains(i) { return .hintBlocker }
            return hint.area.contains(i) ? .hintArea : .none
        }
        guard !model.isSolved, let selected else { return .none }
        if i == selected { return .selected }
        if let digit, game?.values[i] == digit { return .sameDigit }
        if Sudoku.areSeen(i, selected) { return .peer }
        return .none
    }

    private func accessibilityValue(_ i: Int, game: Sudoku.Game?, conflicts: Set<Int>) -> String {
        guard let game else { return "Empty" }
        let v = game.values[i]
        if v != 0 {
            var parts = ["\(v)"]
            if game.isGiven(i) { parts.append("given") }
            if game.hinted.contains(i) { parts.append("from hint") }
            if conflicts.contains(i) { parts.append("conflict") }
            return parts.joined(separator: ", ")
        }
        let notes = game.notes(at: i)
        if notes.isEmpty { return "Empty" }
        return "Notes " + notes.map(String.init).joined(separator: ", ")
    }
}

/// Thin cell lines and thicker 3×3 box lines.
private struct GridLines: View {
    var body: some View {
        Canvas { ctx, size in
            let step = size.width / 9
            var thin = Path(), thick = Path()
            for k in 1..<9 {
                let p = CGFloat(k) * step
                var line = Path()
                line.move(to: CGPoint(x: p, y: 0)); line.addLine(to: CGPoint(x: p, y: size.height))
                line.move(to: CGPoint(x: 0, y: p)); line.addLine(to: CGPoint(x: size.width, y: p))
                if k % 3 == 0 { thick.addPath(line) } else { thin.addPath(line) }
            }
            ctx.stroke(thin, with: .color(SudokuPalette.cellLine), lineWidth: 1)
            ctx.stroke(thick, with: .color(SudokuPalette.boxLine), lineWidth: SudokuBoardView.boxLineWidth(size.width) * 0.8)
        }
    }
}

struct SudokuCellView: View {
    enum Highlight { case none, peer, sameDigit, selected, hintArea, hintBlocker, hintTarget }

    let value: Int
    let isGiven: Bool
    let notes: UInt16
    let highlight: Highlight
    let isConflict: Bool
    let noteHighlight: Int?
    let size: CGFloat
    let pop: Int
    let wave: Int
    let waveDelay: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            waveFlash
            content
                .keyframeAnimator(initialValue: CGFloat(1), trigger: pop) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(reduceMotion ? CGFloat(1) : CGFloat(1.22), duration: 0.1)
                        SpringKeyframe(CGFloat(1), duration: 0.22)
                    }
                }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var content: some View {
        if value != 0 {
            Text("\(value)")
                .font(.system(size: size * 0.6, weight: isGiven ? .semibold : .medium, design: .rounded))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .contentTransition(.identity)
        } else if notes != 0 {
            NotesGrid(notes: notes, highlight: noteHighlight, size: size)
        }
    }

    private var waveFlash: some View {
        Rectangle()
            .fill(SudokuPalette.wave)
            .keyframeAnimator(initialValue: 0.0, trigger: wave) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.0, duration: max(0.001, waveDelay))
                    LinearKeyframe(reduceMotion ? 0.5 : 0.9, duration: 0.1)
                    CubicKeyframe(0.0, duration: 0.45)
                }
            }
    }

    private var textColor: Color {
        if isConflict && !isGiven { return SudokuPalette.conflict }
        return isGiven ? SudokuPalette.given : SudokuPalette.player
    }

    private var background: Color {
        switch highlight {
        case .selected: return SudokuPalette.selected
        case .hintTarget: return SudokuPalette.hintTarget
        case .hintBlocker: return SudokuPalette.hintBlocker
        case _ where isConflict: return SudokuPalette.conflictFill
        case .hintArea: return SudokuPalette.hintArea
        case .sameDigit: return SudokuPalette.sameDigit
        case .peer: return SudokuPalette.peer
        case .none: return .clear
        }
    }
}

/// Pencil marks laid out as a 3×3 mini grid.
private struct NotesGrid: View {
    let notes: UInt16
    let highlight: Int?
    let size: CGFloat

    var body: some View {
        let mini = size / 3.3
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(1...3, id: \.self) { c in
                        let d = r * 3 + c
                        let on = notes & (1 << UInt16(d)) != 0
                        let emphasized = on && d == highlight
                        Text(on ? "\(d)" : " ")
                            .font(.system(size: mini * 0.78, weight: emphasized ? .heavy : .medium, design: .rounded))
                            .foregroundStyle(emphasized ? Color.white : SudokuPalette.note)
                            .frame(width: mini, height: mini)
                            .background {
                                if emphasized { Circle().fill(SudokuPalette.player).padding(mini * 0.04) }
                            }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
