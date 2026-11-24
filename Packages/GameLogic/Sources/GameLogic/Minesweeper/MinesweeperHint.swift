extension Minesweeper {
    /// One logical step the player can take next, with the reasoning in plain words.
    public struct Hint: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// No mines yet: any first tap is safe.
            case start
            /// `cells` are safe to reveal.
            case safe
            /// `cells` are mines to flag.
            case mine
            /// `cells` are flagged but can't be mines.
            case wrongFlag
        }

        public let kind: Kind
        /// The numbers the reasoning reads (none for the start or the mine count).
        public let clues: [GridPoint]
        /// The squares the hint is about.
        public let cells: [GridPoint]
        public let title: String
        public let explanation: String
    }

    /// Finds the next deduction from what the player can see: revealed numbers only (flags are
    /// trusted only once they are proven), using the same rules as the no-guess `Solver`.
    enum Hinter {
        static func hint(for state: State) -> Hint? {
            switch state.status {
            case .won, .lost: return nil
            case .ready:
                let center = GridPoint(row: state.rows / 2, col: state.cols / 2)
                return Hint(kind: .start, clues: [], cells: [center], title: "Tap anywhere",
                            explanation: "Your first tap is always safe and opens up an area. The middle is a good place to start.")
            case .playing:
                var finder = Finder(state)
                return finder.next()
            }
        }
    }

    private struct Finder {
        let state: State
        /// Proven mines (not necessarily flagged yet).
        var mines: Set<GridPoint> = []

        init(_ state: State) { self.state = state }

        struct Clue {
            let at: GridPoint
            let number: Int
            /// Hidden squares around it that aren't proven mines.
            let open: [GridPoint]
            /// Proven mines around it.
            let found: Int
            var needed: Int { number - found }
        }

        func clue(at p: GridPoint) -> Clue? {
            let cell = state[p]
            guard cell.isRevealed, !cell.isMine, cell.adjacent > 0 else { return nil }
            var open: [GridPoint] = []
            var found = 0
            for n in state.neighbors(of: p) where !state[n].isRevealed {
                if mines.contains(n) { found += 1 } else { open.append(n) }
            }
            return open.isEmpty ? nil : Clue(at: p, number: cell.adjacent, open: open, found: found)
        }

        enum Step {
            case safe([GridPoint], clues: [GridPoint], reason: String)
            case mine([GridPoint], clues: [GridPoint], reason: String)
        }

        mutating func next() -> Hint? {
            // Proven mines the player already flagged teach nothing; keep deducing past them.
            for _ in 0..<(state.rows * state.cols) {
                guard let step = singleSafe() ?? singleMine() ?? pair() ?? mineCount() else { return nil }
                switch step {
                case let .safe(cells, clues, reason):
                    let unflagged = cells.filter { !state[$0].isFlagged }
                    if !unflagged.isEmpty {
                        return Hint(kind: .safe, clues: clues, cells: unflagged,
                                    title: unflagged.count == 1 ? "A safe square" : "Safe squares",
                                    explanation: reason + (unflagged.count == 1 ? " Reveal it." : " Reveal them."))
                    }
                    return Hint(kind: .wrongFlag, clues: clues, cells: cells,
                                title: cells.count == 1 ? "A flag to move" : "Flags to move",
                                explanation: reason + (cells.count == 1 ? " That flag is on a safe square."
                                                                       : " Those flags are on safe squares."))
                case let .mine(cells, clues, reason):
                    let unflagged = cells.filter { !state[$0].isFlagged }
                    if !unflagged.isEmpty {
                        return Hint(kind: .mine, clues: clues, cells: unflagged,
                                    title: unflagged.count == 1 ? "A mine to flag" : "Mines to flag",
                                    explanation: reason + (unflagged.count == 1 ? " Flag it." : " Flag them."))
                    }
                    mines.formUnion(cells)
                }
            }
            return nil
        }

        // MARK: Rules

        private var clues: [Clue] { state.allPoints.compactMap(clue(at:)) }

        private func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

        /// A number whose mines are all found: the rest around it are safe.
        private func singleSafe() -> Step? {
            guard let c = clues.first(where: { $0.needed == 0 }) else { return nil }
            let reason = c.number == 1
                ? "This 1 already touches its mine, so the other squares around it are safe."
                : "This \(c.number) already touches all \(c.number) of its mines, so the other squares around it are safe."
            return .safe(c.open, clues: [c.at], reason: reason)
        }

        /// A number with exactly as many hidden squares as missing mines: they're all mines.
        private func singleMine() -> Step? {
            guard let c = clues.first(where: { $0.needed > 0 && $0.needed == $0.open.count }) else { return nil }
            let them = c.open.count == 1 ? "it must be a mine" : "they must all be mines"
            let reason = c.found == 0
                ? "This \(c.number) touches only \(plural(c.open.count, "hidden square")), so \(them)."
                : "This \(c.number) already touches \(plural(c.found, "mine")) and needs \(c.needed) more, "
                    + "with just \(plural(c.open.count, "hidden square")) left around it, so \(them)."
            return .mine(c.open, clues: [c.at], reason: reason)
        }

        /// Two numbers that share hidden squares.
        private func pair() -> Step? {
            let all = clues
            for a in all {
                let setA = Set(a.open)
                for b in all where b.at != a.at && !setA.isDisjoint(with: b.open) {
                    let setB = Set(b.open)
                    let onlyA = a.open.filter { !setB.contains($0) }
                    let onlyB = b.open.filter { !setA.contains($0) }
                    // A needs more mines than the shared squares can hold: its own squares are mines,
                    // and B's mines all sit in the shared squares.
                    if !onlyA.isEmpty, a.needed - b.needed == onlyA.count {
                        let shared = "at most \(plural(b.needed, "mine")) can be in the squares it shares with this \(b.number)"
                        if !onlyB.isEmpty {
                            return .safe(onlyB, clues: [a.at, b.at], reason:
                                "This \(a.number) needs \(plural(a.needed, "more mine")), but \(shared). "
                                + "So the \(b.number)'s mines are all in the shared squares, and its other squares are safe.")
                        }
                        return .mine(onlyA, clues: [a.at, b.at], reason:
                            "This \(a.number) needs \(plural(a.needed, "more mine")), but \(shared). "
                            + (onlyA.count == 1 ? "So its one other square must be a mine."
                                                : "So its \(onlyA.count) other squares must all be mines."))
                    }
                    // Every hidden square around A also touches B, and both need the same count.
                    if onlyA.isEmpty, !onlyB.isEmpty, a.needed == b.needed {
                        return .safe(onlyB, clues: [a.at, b.at], reason:
                            "Every hidden square around this \(a.number) also touches this \(b.number), and both need "
                            + "\(plural(a.needed, "more mine")). So the \(b.number)'s mines are all in the shared squares, "
                            + "and its other squares are safe.")
                    }
                }
            }
            return nil
        }

        /// Counting the mines left, once the numbers run out.
        private func mineCount() -> Step? {
            let hidden = state.allPoints.filter { !state[$0].isRevealed && !mines.contains($0) }
            guard !hidden.isEmpty else { return nil }
            let left = state.mineCount - mines.count
            if left == 0 {
                return .safe(hidden, clues: [], reason:
                    "All \(state.mineCount) mines are accounted for, so every other hidden square is safe.")
            }
            if left == hidden.count {
                return .mine(hidden, clues: [], reason:
                    "Exactly \(plural(left, "mine")) remain for the last \(plural(hidden.count, "hidden square")), "
                    + "so they're all mines.")
            }
            return nil
        }
    }
}

extension Minesweeper.State {
    /// The next logical step from what's on screen, or nil when the game is over or the visible
    /// numbers don't decide anything.
    public func hint() -> Minesweeper.Hint? { Minesweeper.Hinter.hint(for: self) }
}
