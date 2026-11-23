extension Sudoku {
    /// A hint, explained: which square, its answer, and why, in words a player can follow.
    public struct Hint: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// The answer follows by logic from what's on the board.
            case deduction
            /// The square holds a wrong digit; the answer replaces it.
            case mistake
            /// No supported technique applies; the answer is simply shown.
            case reveal
        }

        public let kind: Kind
        public let cell: Int
        /// The correct digit for `cell`.
        public let digit: Int
        /// The technique that finds it (deductions only).
        public let technique: Technique?
        /// The row, column or box the reasoning is about, if it's about one.
        public let unit: Unit?
        /// Squares to highlight while explaining (the unit, or the square's row, column and box).
        public let area: [Int]
        /// Squares holding the digits the reasoning relies on.
        public let blockers: [Int]
        public let title: String
        public let explanation: String
    }
}

extension Sudoku.Hint {
    typealias S = Sudoku

    static func mistake(at cell: Int, digit: Int, values: [Int]) -> Self {
        let wrong = values[cell]
        let clash = S.units(of: cell).first { unit in unit.cells.contains { $0 != cell && values[$0] == wrong } }
        let explanation: String
        var blockers: [Int] = []
        if let clash {
            blockers = clash.cells.filter { $0 != cell && values[$0] == wrong }
            explanation = "There's already a \(wrong) in this \(clash.name), so this \(wrong) can't stay."
        } else {
            explanation = "This \(wrong) doesn't fit: the puzzle's only solution has a different number here, "
                + "and later steps would go wrong because of it."
        }
        return .init(kind: .mistake, cell: cell, digit: digit, technique: nil, unit: clash,
                     area: clash?.cells ?? [], blockers: blockers, title: "Check This Square", explanation: explanation)
    }

    static func reveal(at cell: Int, digit: Int) -> Self {
        .init(kind: .reveal, cell: cell, digit: digit, technique: nil, unit: nil, area: S.peers[cell], blockers: [],
              title: "Answer",
              explanation: "No step this app knows how to explain applies right now, so this hint just shows "
                + "the answer for this square: \(digit).")
    }

    /// Explains a placement found by `technique` (a naked or hidden single), using the board the
    /// player sees. `candidates` are the solver's, after any `advanced` eliminations.
    static func deduction(_ technique: S.Technique, at cell: Int, digit: Int, values: [Int],
                          candidates: [UInt16], advanced: S.Technique?) -> Self {
        let prefix = advanced.map {
            "This one takes an advanced step first: \($0.title) rules some numbers out. Then "
        } ?? ""
        func sentence(_ text: String) -> String {
            prefix.isEmpty ? text : prefix + text.prefix(1).lowercased() + text.dropFirst()
        }
        switch technique {
        case .hiddenSingle:
            return hiddenSingle(at: cell, digit: digit, values: values, candidates: candidates, sentence: sentence)
        default:
            let seen = Set(S.peers[cell].map { values[$0] }).subtracting([0])
            let text = seen == Set(1...9).subtracting([digit])
                ? "Its row, column and box already hold every number except \(digit), so this square must be \(digit)."
                : "Every number except \(digit) is ruled out for this square, so it must be \(digit)."
            return .init(kind: .deduction, cell: cell, digit: digit, technique: technique, unit: nil,
                         area: S.peers[cell], blockers: [], title: technique.title, explanation: sentence(text))
        }
    }

    private static func hiddenSingle(at cell: Int, digit: Int, values: [Int], candidates: [UInt16],
                                     sentence: (String) -> String) -> Self {
        let units = S.units(of: cell)
        let order = [units[2], units[0], units[1]]   // box first: the most natural to scan
        // Plain case: every other empty square of the unit already sees `digit` on the board.
        for unit in order {
            let others = unit.cells.filter { $0 != cell && values[$0] == 0 }
            var blockers: [Int] = []
            let plain = others.allSatisfy { other in
                guard let b = S.peers[other].first(where: { values[$0] == digit }) else { return false }
                if !blockers.contains(b) { blockers.append(b) }
                return true
            }
            if plain {
                let text = others.isEmpty
                    ? "This is the last empty square in its \(unit.name), and \(digit) is the number it's missing."
                    : "In this \(unit.name), \(digit) can only go here: every other empty square already sees a \(digit)."
                return .init(kind: .deduction, cell: cell, digit: digit, technique: .hiddenSingle, unit: unit,
                             area: unit.cells, blockers: blockers, title: S.Technique.hiddenSingle.title,
                             explanation: sentence(text))
            }
        }
        // After advanced eliminations: the unit where only this square can still take `digit`.
        let bit = S.bit(digit)
        let unit = order.first { u in u.cells.allSatisfy { $0 == cell || values[$0] != 0 || candidates[$0] & bit == 0 } }
            ?? order[0]
        return .init(kind: .deduction, cell: cell, digit: digit, technique: .hiddenSingle, unit: unit,
                     area: unit.cells, blockers: [], title: S.Technique.hiddenSingle.title,
                     explanation: sentence("In this \(unit.name), \(digit) has only one place left: here."))
    }
}

extension Sudoku.Unit {
    /// "row", "column" or "box", for sentences.
    public var name: String {
        switch self {
        case .row: "row"
        case .column: "column"
        case .box: "box"
        }
    }
}
