import SwiftUI
import GameLogic

/// Level select: every bundled picture, grouped by size, with progress.
struct NonogramsView: View {
    @State private var progress = NonogramsProgress.shared
    @State private var opened: OpenPuzzle?
    @State private var didAutoResume = false
    @Environment(\.gameLaunch) private var launch

    private let accent = GameID.nonograms.accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                summary
                ForEach(Nonograms.Size.allCases) { size in
                    section(size)
                }
            }
            .padding(16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .gameChrome(.nonograms, rules: Self.rules,
                    stats: NonogramsPuzzleModel.statsVariants,
                    newGame: Nonograms.Size.allCases.map { size in
                        NewGameOption(title: "\(size.title) · \(size.dimension)×\(size.dimension)") {
                            progress.nextPuzzle(of: size).map(open)
                        }
                    })
        .navigationDestination(item: $opened) { open in
            NonogramsPuzzleView(model: open.model) { next in self.open(next) }
                .id(open.id)
        }
        .onAppear {
            // Coming back via "Continue Playing" on the home screen continues the last puzzle;
            // the Nonograms card opens the library instead.
            guard !didAutoResume else { return }
            didAutoResume = true
            #if DEBUG
            applyDemoArguments()
            #endif
            if launch == .resume, let session = progress.session, let puzzle = Nonograms.puzzle(id: session.puzzleID) {
                open(puzzle)
            }
        }
    }

    /// Creates the puzzle's model once, here, rather than in a view initializer that may run repeatedly.
    private func open(_ puzzle: Nonograms.Puzzle) {
        opened = OpenPuzzle(model: NonogramsPuzzleModel(puzzle: puzzle))
    }

    #if DEBUG
    /// `-nonogramsDemo <solvedPerSize> [puzzleID]` fakes progress (and opens a half-done puzzle) for screenshots.
    private func applyDemoArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-nonogramsDemo"), i + 1 < args.count, let solved = Int(args[i + 1]) else { return }
        for size in Nonograms.Size.allCases {
            for (n, puzzle) in Nonograms.puzzles(of: size).enumerated() {
                if n < solved {
                    progress.update(puzzle) { $0.solved = true; $0.bestTime = Double(40 + n * 17) }
                } else if n == solved {
                    var board = Nonograms.Board(for: puzzle)
                    for p in board.allPoints where p.row < puzzle.height / 2 { board[p] = puzzle[p] ? .filled : .crossed }
                    progress.update(puzzle) { $0.board = board; $0.elapsed = 75 }
                }
            }
        }
        if i + 2 < args.count, let puzzle = Nonograms.puzzle(id: args[i + 2]) {
            open(puzzle)
        }
    }
    #endif

    // MARK: Summary

    private var summary: some View {
        let solved = progress.solvedCount()
        let total = Nonograms.library.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Picture Gallery")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(solved == total ? "Every picture revealed. Bravo!" : "Solve the clues to reveal each picture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(solved)/\(total)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            ProgressView(value: Double(solved), total: Double(total))
                .tint(accent)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solved \(solved) of \(total) pictures")
    }

    // MARK: Sections

    private func section(_ size: Nonograms.Size) -> some View {
        let puzzles = Nonograms.puzzles(of: size)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(size.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("\(size.dimension)×\(size.dimension)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.solvedCount(size)) of \(puzzles.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)], spacing: 12) {
                ForEach(Array(puzzles.enumerated()), id: \.element.id) { index, puzzle in
                    Button {
                        open(puzzle)
                    } label: {
                        PuzzleCard(puzzle: puzzle, number: index + 1, entry: progress.entry(puzzle))
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .accessibilityIdentifier("puzzle.\(puzzle.id)")
                }
            }
        }
    }

    static let rules = HowToPlay(
        summary: "Use the number clues to fill in cells and reveal a hidden picture.",
        sections: [
            .init(title: "Clues", symbol: "number", points: [
                "Numbers beside each row and above each column list its runs of filled cells, in order.",
                "“3 1” means a run of three, then at least one gap, then a single cell.",
                "A line's clues fade once that line matches them.",
            ]),
            .init(title: "Marking", symbol: "hand.draw", points: [
                "Tap a cell to fill it, or drag to fill a whole stretch of a row or column.",
                "Switch to Cross to mark cells you know are empty.",
                "Start a stroke on a marked cell to erase along the line.",
            ]),
            .init(title: "Help when stuck", symbol: "lightbulb", points: [
                "Check briefly highlights any cells that don't match the picture.",
                "Hint explains one square you can work out from what you already have, then Show Answer marks it.",
                "Every puzzle can be solved by logic alone — no guessing needed.",
            ]),
        ]
    )
}

/// A navigation item that carries the puzzle's model.
private struct OpenPuzzle: Hashable, Identifiable {
    let model: NonogramsPuzzleModel
    var id: String { model.puzzle.id }

    static func == (a: Self, b: Self) -> Bool { a.model === b.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }
}

// MARK: - Cards

private struct PuzzleCard: View {
    let puzzle: Nonograms.Puzzle
    let number: Int
    let entry: NonogramsProgress.Entry

    var body: some View {
        let started = entry.board.map { !$0.isBlank } ?? false
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(entry.solved ? Color(hex: puzzle.color).opacity(0.12) : Theme.well)
                if entry.solved {
                    PixelArtView(width: puzzle.width, height: puzzle.height, cells: puzzle.solution,
                                 color: Color(hex: puzzle.color))
                        .padding(12)
                } else if started, let board = entry.board {
                    PixelArtView(width: board.width, height: board.height,
                                 cells: board.cells.map { $0 == .filled }, color: NonoPalette.ink.opacity(0.55))
                        .padding(12)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, GameID.nonograms.accent)
                                .padding(6)
                        }
                } else {
                    VStack(spacing: 2) {
                        Text("?")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(GameID.nonograms.accent)
                        Text("\(puzzle.width)×\(puzzle.height)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(spacing: 1) {
                Text(entry.solved ? puzzle.title : "Puzzle \(number)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption(started: started))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(started: started))
        .accessibilityAddTraits(.isButton)
    }

    private func caption(started: Bool) -> String {
        if entry.solved { return entry.bestTime.map { "Best \($0.clockString)" } ?? "Solved" }
        return started ? "In progress" : "New"
    }

    private func accessibilityText(started: Bool) -> String {
        let name = "\(puzzle.size?.title ?? "") puzzle \(number), \(puzzle.width) by \(puzzle.height)"
        if entry.solved { return "\(name), solved: \(puzzle.title)" + (entry.bestTime.map { ", best time \($0.clockString)" } ?? "") }
        return started ? "\(name), in progress" : "\(name), not started"
    }
}

/// Draws a bitmap as crisp square pixels, centered in the available space.
struct PixelArtView: View {
    let width: Int
    let height: Int
    let cells: [Bool]
    let color: Color
    var gap: CGFloat = 0.08

    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / CGFloat(width), size.height / CGFloat(height))
            let origin = CGPoint(x: (size.width - cell * CGFloat(width)) / 2, y: (size.height - cell * CGFloat(height)) / 2)
            let inset = cell * gap / 2
            for i in cells.indices where cells[i] {
                let rect = CGRect(x: origin.x + CGFloat(i % width) * cell + inset,
                                  y: origin.y + CGFloat(i / width) * cell + inset,
                                  width: cell - inset * 2, height: cell - inset * 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.18), with: .color(color))
            }
        }
        .aspectRatio(CGFloat(width) / CGFloat(height), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum NonoPalette {
    /// Filled cells while solving.
    static let ink = Color(light: Color(hex: 0x30344A), dark: Color(hex: 0xD9DDEA))
    static let cross = Color(light: Color(hex: 0x9097AB), dark: Color(hex: 0x6E7590))
    static let mistake = Color(hex: 0xE5484D)
    static let hint = Color(hex: 0xF2B705)
    static let gridLine = Color(light: Color(hex: 0xD3D7E2), dark: Color(hex: 0x323747))
    static let majorLine = Color(light: Color(hex: 0x8D93A6), dark: Color(hex: 0x6A7189))
    static let focus = Color(light: Color(hex: 0xFF6F61, opacity: 0.10), dark: Color(hex: 0xFF6F61, opacity: 0.14))
}
