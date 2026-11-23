import SwiftUI
import GameLogic

/// Clues plus the grid, sized to fit the available space (clue font scales with the cells).
struct NonogramBoard: View {
    let model: NonogramsPuzzleModel

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var dragging = false
    @GestureState private var strokeActive = false

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(puzzle: model.puzzle, available: geo.size)
            let puzzle = model.puzzle

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    Color.clear.frame(width: layout.left, height: layout.top)
                    columnClues(layout)
                }
                HStack(alignment: .top, spacing: 0) {
                    rowClues(layout)
                    grid(layout)
                        .frame(width: layout.cell * CGFloat(puzzle.width), height: layout.cell * CGFloat(puzzle.height))
                        .contentShape(Rectangle())
                        .gesture(dragGesture(layout), including: voiceOver ? .subviews : .all)
                        .onGestureCancelled(strokeActive) {
                            // Keep what was painted, as if the finger had lifted.
                            guard dragging else { return }
                            dragging = false
                            model.endStroke()
                        }
                }
            }
            .frame(width: layout.totalWidth, height: layout.totalHeight)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Clues

    private func columnClues(_ layout: Layout) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<model.puzzle.width, id: \.self) { c in
                let clue = model.puzzle.columnClues[c]
                let done = !model.isSolved && model.isColumnDone(c)
                VStack(spacing: layout.cell * 0.02) {
                    ForEach(Array(displayClue(clue).enumerated()), id: \.offset) { _, n in
                        clueText(n, layout: layout)
                    }
                }
                .padding(.vertical, layout.cell * 0.15)
                .frame(width: layout.cell)
                .frame(maxHeight: layout.top, alignment: .bottom)
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: layout.cell * 0.25, style: .continuous)
                        .fill(model.highlightsColumn(c) ? GameID.nonograms.accent.opacity(0.16) : .clear)
                        .padding(.horizontal, layout.cell * 0.06)
                }
                .opacity(model.isSolved ? 0.35 : done ? 0.32 : 1)
                .animation(.easeOut(duration: 0.2), value: done)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Column \(c + 1) clue")
                .accessibilityValue(clueDescription(clue, done: done))
            }
        }
        .frame(height: layout.top, alignment: .bottom)
    }

    private func rowClues(_ layout: Layout) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<model.puzzle.height, id: \.self) { r in
                let clue = model.puzzle.rowClues[r]
                let done = !model.isSolved && model.isRowDone(r)
                HStack(spacing: layout.cell * 0.3) {
                    ForEach(Array(displayClue(clue).enumerated()), id: \.offset) { _, n in
                        clueText(n, layout: layout)
                    }
                }
                .padding(.horizontal, layout.cell * 0.18)
                .frame(height: layout.cell)
                .frame(maxWidth: layout.left, alignment: .trailing)
                .background(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: layout.cell * 0.25, style: .continuous)
                        .fill(model.highlightsRow(r) ? GameID.nonograms.accent.opacity(0.16) : .clear)
                        .padding(.vertical, layout.cell * 0.06)
                }
                .opacity(model.isSolved ? 0.35 : done ? 0.32 : 1)
                .animation(.easeOut(duration: 0.2), value: done)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Row \(r + 1) clue")
                .accessibilityValue(clueDescription(clue, done: done))
            }
        }
        .frame(width: layout.left)
    }

    private func displayClue(_ clue: [Int]) -> [Int] { clue.isEmpty ? [0] : clue }

    private func clueText(_ n: Int, layout: Layout) -> some View {
        Text("\(n)")
            .font(.system(size: layout.clueFont, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(n == 0 ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
    }

    private func clueDescription(_ clue: [Int], done: Bool) -> String {
        let numbers = clue.isEmpty ? "0, empty line" : clue.map(String.init).joined(separator: ", ")
        return done ? "\(numbers), complete" : numbers
    }

    // MARK: Grid

    private func grid(_ layout: Layout) -> some View {
        let puzzle = model.puzzle
        let color = Color(hex: puzzle.color)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.surface)
            VStack(spacing: 0) {
                ForEach(0..<puzzle.height, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<puzzle.width, id: \.self) { c in
                            let p = GridPoint(row: r, col: c)
                            NonoCellView(mark: model.board[p], size: layout.cell,
                                         focused: model.highlightsRow(r) || model.highlightsColumn(c),
                                         mistake: model.flagged.contains(p), hinted: model.hinted == p,
                                         solved: model.isSolved, color: color,
                                         revealDelay: model.justSolved && !reduceMotion ? Double(r + c) * 0.035 : 0,
                                         reduceMotion: reduceMotion)
                                .equatable()
                                .accessibilityElement()
                                .accessibilityLabel("Row \(r + 1), column \(c + 1)")
                                .accessibilityValue(accessibilityValue(p))
                                .accessibilityIdentifier("nono.\(r).\(c)")
                                .accessibilityAction { model.apply(model.tool == .fill ? .filled : .crossed, at: p) }
                                .accessibilityActions {
                                    if !model.isSolved {
                                        Button("Fill") { model.apply(.filled, at: p) }
                                        Button("Cross out") { model.apply(.crossed, at: p) }
                                        Button("Clear") { model.apply(.empty, at: p) }
                                    }
                                }
                        }
                    }
                }
            }
            GridLines(width: puzzle.width, height: puzzle.height, cell: layout.cell)
                .opacity(model.isSolved ? 0 : 1)
                .animation(.easeOut(duration: 0.6).delay(model.justSolved ? 0.4 : 0), value: model.isSolved)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: max(4, layout.cell * 0.2), style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puzzle grid")
        .accessibilityIdentifier("nonogramGrid")
    }

    private func accessibilityValue(_ p: GridPoint) -> String {
        let state = switch model.board[p] {
        case .filled: "Filled"
        case .crossed: model.isSolved ? "Empty" : "Crossed out"
        case .empty: "Empty"
        }
        return model.flagged.contains(p) ? "\(state), mistake" : state
    }

    private func dragGesture(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .tracking($strokeActive)
            .onChanged { value in
                let p = layout.point(at: value.location, puzzle: model.puzzle)
                if !dragging {
                    guard model.board.contains(p) else { return }
                    dragging = true
                    withAnimation(.easeOut(duration: 0.08)) { model.beginStroke(at: p) }
                } else {
                    let clamped = GridPoint(row: min(max(p.row, 0), model.puzzle.height - 1),
                                            col: min(max(p.col, 0), model.puzzle.width - 1))
                    withAnimation(.easeOut(duration: 0.08)) { model.continueStroke(to: clamped) }
                }
            }
            .onEnded { _ in
                dragging = false
                withAnimation(.easeOut(duration: 0.12)) { model.endStroke() }
            }
    }

    // MARK: Layout

    struct Layout {
        let cell: CGFloat
        let left: CGFloat
        let top: CGFloat
        let clueFont: CGFloat
        let totalWidth: CGFloat
        let totalHeight: CGFloat

        /// Clue widths/heights are measured in cell units so everything scales together.
        init(puzzle: Nonograms.Puzzle, available: CGSize) {
            func units(_ clue: [Int]) -> CGFloat {
                let numbers = clue.isEmpty ? [0] : clue
                return numbers.reduce(CGFloat(0.36)) { $0 + ($1 >= 10 ? 0.78 : 0.5) + 0.3 }
            }
            let leftUnits = max(1.2, puzzle.rowClues.map(units).max() ?? 1)
            let topUnits = max(1.2, CGFloat(puzzle.columnClues.map { max(1, $0.count) }.max() ?? 1) * 0.66 + 0.3)
            let byWidth = available.width / (CGFloat(puzzle.width) + leftUnits)
            let byHeight = available.height / (CGFloat(puzzle.height) + topUnits)
            let cell = max(8, min(byWidth, byHeight, 64).rounded(.down))
            self.cell = cell
            left = (leftUnits * cell).rounded(.up)
            top = (topUnits * cell).rounded(.up)
            clueFont = min(22, max(9, cell * 0.56))
            totalWidth = left + cell * CGFloat(puzzle.width)
            totalHeight = top + cell * CGFloat(puzzle.height)
        }

        func point(at location: CGPoint, puzzle: Nonograms.Puzzle) -> GridPoint {
            GridPoint(row: Int((location.y / cell).rounded(.down)), col: Int((location.x / cell).rounded(.down)))
        }
    }
}

// MARK: - Cell

private struct NonoCellView: View, Equatable {
    let mark: Nonograms.Mark
    let size: CGFloat
    let focused: Bool
    let mistake: Bool
    let hinted: Bool
    let solved: Bool
    let color: Color
    let revealDelay: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(focused && !solved ? NonoPalette.focus : .clear)

            if mark == .filled {
                // Solved cells overlap slightly so the picture reads as one seamless shape.
                RoundedRectangle(cornerRadius: solved ? 0 : size * 0.16, style: .continuous)
                    .fill(solved ? color : NonoPalette.ink)
                    .padding(solved ? -0.5 : max(1, size * 0.07))
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7).delay(revealDelay), value: solved)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else if mark == .crossed && !solved {
                CrossGlyph()
                    .stroke(NonoPalette.cross, style: StrokeStyle(lineWidth: max(1.2, size * 0.07), lineCap: .round))
                    .padding(size * 0.3)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            if mistake {
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .stroke(NonoPalette.mistake, lineWidth: max(1.5, size * 0.1))
                    .background(NonoPalette.mistake.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.14))
                    .padding(max(1, size * 0.05))
                    .transition(.opacity)
            }
            if hinted {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .stroke(NonoPalette.hint, lineWidth: max(1.5, size * 0.1))
                    .padding(max(1, size * 0.04))
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct CrossGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// Thin lines between cells, thicker every 5 cells and around the edge.
private struct GridLines: View {
    let width: Int
    let height: Int
    let cell: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var minor = Path(), major = Path()
            for c in 0...width {
                let x = CGFloat(c) * cell
                if c % 5 == 0 || c == width {
                    major.move(to: CGPoint(x: x, y: 0)); major.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            for r in 0...height {
                let y = CGFloat(r) * cell
                if r % 5 == 0 || r == height {
                    major.move(to: CGPoint(x: 0, y: y)); major.addLine(to: CGPoint(x: size.width, y: y))
                } else {
                    minor.move(to: CGPoint(x: 0, y: y)); minor.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            ctx.stroke(minor, with: .color(NonoPalette.gridLine), lineWidth: 1)
            ctx.stroke(major, with: .color(NonoPalette.majorLine), lineWidth: 2)
        }
    }
}
