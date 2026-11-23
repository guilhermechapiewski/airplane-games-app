extension Sudoku {
    /// What changed after a player action (for animations and sounds).
    public struct Outcome: Equatable, Sendable {
        /// Units that became completely and correctly (rule-wise) filled by this action.
        public var completedUnits: [Unit] = []
        /// The placed digit repeats in one of the cell's units.
        public var conflicts = false
        public var solved = false
    }


    /// An in-progress game: the player's digits, notes and full undo history.
    public struct Game: Codable, Equatable, Sendable {
        /// Previous contents of a cell, recorded for undo.
        struct CellChange: Codable, Equatable, Sendable {
            let cell: Int
            let value: Int
            let notes: UInt16
            let hinted: Bool
        }

        public let puzzle: Puzzle
        public private(set) var values: [Int]
        /// Pencil marks per cell (bits 1…9).
        public private(set) var notes: [UInt16]
        /// Cells filled by a hint.
        public private(set) var hinted: Set<Int> = []
        public private(set) var hintsUsed = 0
        private var history: [[CellChange]] = []

        public init(puzzle: Puzzle) {
            self.puzzle = puzzle
            values = puzzle.givens
            notes = [UInt16](repeating: 0, count: cellCount)
        }

        // MARK: Queries

        public var difficulty: Difficulty { puzzle.difficulty }
        public var canUndo: Bool { !history.isEmpty }
        public var undoCount: Int { history.count }
        public var isSolved: Bool { Sudoku.isSolved(values) }
        public var conflicts: Set<Int> { Sudoku.conflicts(in: values) }
        /// Whether the player has made any move that can still be undone.
        public var hasProgress: Bool { !history.isEmpty }

        public func isGiven(_ cell: Int) -> Bool { puzzle.givens[cell] != 0 }
        public func notes(at cell: Int) -> [Int] { Sudoku.digits(in: notes[cell]) }

        /// How many more times `digit` must be placed (never negative).
        public func remaining(_ digit: Int) -> Int {
            max(0, 9 - values.lazy.filter { $0 == digit }.count)
        }

        /// The filled cell whose digit differs from the solution, if any.
        public func isWrong(_ cell: Int) -> Bool {
            values[cell] != 0 && values[cell] != puzzle.solution[cell]
        }

        // MARK: Actions

        /// Writes `digit` into an editable cell and clears that digit from notes in its
        /// row, column and box. Returns `nil` if nothing changed.
        @discardableResult
        public mutating func enter(_ digit: Int, at cell: Int) -> Outcome? {
            guard (1...9).contains(digit), (0..<cellCount).contains(cell), !isGiven(cell),
                  values[cell] != digit else { return nil }
            var changes: [CellChange] = []
            write(digit, at: cell, hinted: false, into: &changes)
            history.append(changes)
            return outcome(after: cell)
        }

        /// Toggles a pencil mark in an empty, editable cell. Returns `false` if not allowed.
        @discardableResult
        public mutating func toggleNote(_ digit: Int, at cell: Int) -> Bool {
            guard (1...9).contains(digit), (0..<cellCount).contains(cell), !isGiven(cell),
                  values[cell] == 0 else { return false }
            history.append([snapshot(cell)])
            notes[cell] ^= bit(digit)
            return true
        }

        /// Clears a player digit, or the notes if the cell has no digit. Returns `false` if nothing changed.
        @discardableResult
        public mutating func erase(at cell: Int) -> Bool {
            guard (0..<cellCount).contains(cell), !isGiven(cell),
                  values[cell] != 0 || notes[cell] != 0 else { return false }
            history.append([snapshot(cell)])
            if values[cell] != 0 {
                values[cell] = 0
                hinted.remove(cell)
            } else {
                notes[cell] = 0
            }
            return true
        }

        /// Reverts the latest action. Returns the cells that changed (the acted-on cell first).
        @discardableResult
        public mutating func undo() -> [Int] {
            guard let changes = history.popLast() else { return [] }
            for change in changes.reversed() {
                values[change.cell] = change.value
                notes[change.cell] = change.notes
                if change.hinted { hinted.insert(change.cell) } else { hinted.remove(change.cell) }
            }
            return changes.map(\.cell)
        }

        /// The most natural next cell to solve, based on the correct digits on the board.
        public func nextHint() -> Hint? {
            guard !isSolved else { return nil }
            // A wrong digit comes first: every deduction after it would rest on it.
            if let wrong = (0..<cellCount).first(where: { values[$0] != 0 && values[$0] != puzzle.solution[$0] }) {
                return Hint.mistake(at: wrong, digit: puzzle.solution[wrong], values: values)
            }
            guard var solver = LogicSolver(values) else { return nil }
            var advanced: Technique?
            while let step = solver.nextStep(maxLevel: 4) {
                if let (cell, digit) = step.placement {
                    return Hint.deduction(step.technique, at: cell, digit: digit, values: values,
                                          candidates: solver.candidates, advanced: advanced)
                }
                advanced = max(advanced ?? step.technique, step.technique)
                guard solver.apply(step) else { break }
            }
            // No technique applies: reveal the open cell with the fewest candidates.
            let open = (0..<cellCount).filter { values[$0] == 0 }
            guard let cell = open.min(by: {
                solver.candidates[$0].nonzeroBitCount < solver.candidates[$1].nonzeroBitCount
            }) else { return nil }
            return Hint.reveal(at: cell, digit: puzzle.solution[cell])
        }

        /// The next hint, counted as used. The board doesn't change until `fill(_:)`.
        public mutating func revealHint() -> Hint? {
            guard let hint = nextHint() else { return nil }
            hintsUsed += 1
            return hint
        }

        /// Writes a hint's answer (undoable). `nil` if the square already holds it.
        @discardableResult
        public mutating func fill(_ hint: Hint) -> Outcome? {
            guard !isGiven(hint.cell), values[hint.cell] != hint.digit else { return nil }
            var changes: [CellChange] = []
            write(hint.digit, at: hint.cell, hinted: true, into: &changes)
            history.append(changes)
            return outcome(after: hint.cell)
        }

        /// Counts and fills the next hint in one go.
        @discardableResult
        public mutating func applyHint() -> (hint: Hint, outcome: Outcome)? {
            guard let hint = revealHint(), let outcome = fill(hint) else { return nil }
            return (hint, outcome)
        }

        // MARK: Internals

        private func snapshot(_ cell: Int) -> CellChange {
            CellChange(cell: cell, value: values[cell], notes: notes[cell], hinted: hinted.contains(cell))
        }

        private mutating func write(_ digit: Int, at cell: Int, hinted isHint: Bool, into changes: inout [CellChange]) {
            changes.append(snapshot(cell))
            values[cell] = digit
            notes[cell] = 0
            if isHint { hinted.insert(cell) } else { hinted.remove(cell) }
            let b = bit(digit)
            for p in peers[cell] where notes[p] & b != 0 {
                changes.append(snapshot(p))
                notes[p] &= ~b
            }
        }

        private func outcome(after cell: Int) -> Outcome {
            var result = Outcome()
            let digit = values[cell]
            result.conflicts = peers[cell].contains { values[$0] == digit }
            for unit in units(of: cell) {
                let cells = unit.cells
                let digits = Set(cells.map { values[$0] })
                if digits.count == 9 && !digits.contains(0) { result.completedUnits.append(unit) }
            }
            result.solved = isSolved
            return result
        }
    }
}
