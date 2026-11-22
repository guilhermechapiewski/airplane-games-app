extension Sudoku {
    /// Human solving techniques, used to grade puzzles and pick hints.
    public enum Technique: String, CaseIterable, Codable, Sendable, Comparable {
        case nakedSingle, hiddenSingle
        case lockedCandidates, nakedPair, hiddenPair, nakedTriple
        case hiddenTriple, xWing, xyWing, swordfish

        /// 1 = easy … 4 = expert.
        public var level: Int {
            switch self {
            case .nakedSingle: 1
            case .hiddenSingle: 2
            case .lockedCandidates, .nakedPair, .hiddenPair, .nakedTriple: 3
            case .hiddenTriple, .xWing, .xyWing, .swordfish: 4
            }
        }

        public var title: String {
            switch self {
            case .nakedSingle: "Last Possible Number"
            case .hiddenSingle: "Only Spot Left"
            case .lockedCandidates: "Pointing Numbers"
            case .nakedPair: "Naked Pair"
            case .hiddenPair: "Hidden Pair"
            case .nakedTriple: "Naked Triple"
            case .hiddenTriple: "Hidden Triple"
            case .xWing: "X-Wing"
            case .xyWing: "XY-Wing"
            case .swordfish: "Swordfish"
            }
        }

        public static func < (a: Technique, b: Technique) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    /// One deduction: either a placement or a set of candidate eliminations.
    public struct Step: Equatable, Sendable {
        public var technique: Technique
        public var placement: (cell: Int, digit: Int)?
        /// Cell index → digits removed from its candidates.
        public var eliminations: [Int: UInt16] = [:]

        public static func == (a: Step, b: Step) -> Bool {
            a.technique == b.technique && a.placement?.cell == b.placement?.cell
                && a.placement?.digit == b.placement?.digit && a.eliminations == b.eliminations
        }
    }

    /// Result of solving a puzzle with human techniques only.
    public struct Grade: Equatable, Sendable {
        /// `true` if the techniques were enough to fill the whole grid.
        public var solved: Bool
        /// The hardest technique that was required (nil if nothing was empty).
        public var hardest: Technique?
        public var techniques: Set<Technique>

        /// Highest technique level used: 0 (nothing to do) … 4, or 5 when unsolved.
        public var level: Int { solved ? (hardest?.level ?? 0) : 5 }

        public var difficulty: Difficulty {
            switch level {
            case ...1: .easy
            case 2: .medium
            case 3: .hard
            default: .expert
            }
        }
    }

    /// Grades a puzzle by solving it with the easiest available technique at every step.
    public static func grade(_ grid: [Int], maxLevel: Int = 4) -> Grade {
        guard var solver = LogicSolver(grid) else { return Grade(solved: false, hardest: nil, techniques: []) }
        return solver.solve(maxLevel: maxLevel)
    }
}

/// A candidate-based solver that applies human techniques, easiest first.
struct LogicSolver {
    private(set) var values: [Int]
    private(set) var candidates: [UInt16]

    /// Fails if the grid is malformed or contradictory (an empty cell has no candidates).
    init?(_ grid: [Int]) {
        guard grid.count == Sudoku.cellCount, Sudoku.conflicts(in: grid).isEmpty else { return nil }
        values = grid
        candidates = (0..<81).map { Sudoku.candidates(in: grid, at: $0) }
        for i in 0..<81 where values[i] == 0 && candidates[i] == 0 { return nil }
    }

    var isComplete: Bool { !values.contains(0) }

    mutating func solve(maxLevel: Int) -> Sudoku.Grade {
        var used = Set<Sudoku.Technique>()
        while !isComplete, let step = nextStep(maxLevel: maxLevel) {
            used.insert(step.technique)
            guard apply(step) else { break }
        }
        return Sudoku.Grade(solved: isComplete && Sudoku.isSolved(values), hardest: used.max(), techniques: used)
    }

    /// Applies a step. Returns `false` if it led to a contradiction.
    @discardableResult
    mutating func apply(_ step: Sudoku.Step) -> Bool {
        if let (cell, digit) = step.placement {
            place(digit, at: cell)
        }
        for (cell, mask) in step.eliminations {
            candidates[cell] &= ~mask
            if values[cell] == 0 && candidates[cell] == 0 { return false }
        }
        for i in 0..<81 where values[i] == 0 && candidates[i] == 0 { return false }
        return true
    }

    mutating func place(_ digit: Int, at cell: Int) {
        values[cell] = digit
        candidates[cell] = 0
        let b = Sudoku.bit(digit)
        for p in Sudoku.peers[cell] { candidates[p] &= ~b }
    }

    /// The easiest deduction available, considering techniques up to `maxLevel`.
    func nextStep(maxLevel: Int = 4) -> Sudoku.Step? {
        if let s = nakedSingle() { return s }
        if maxLevel >= 2, let s = hiddenSingle() { return s }
        if maxLevel >= 3 {
            if let s = lockedCandidates() { return s }
            if let s = nakedSubset(size: 2) { return s }
            if let s = hiddenSubset(size: 2) { return s }
            if let s = nakedSubset(size: 3) { return s }
        }
        if maxLevel >= 4 {
            if let s = hiddenSubset(size: 3) { return s }
            if let s = fish(size: 2) { return s }
            if let s = xyWing() { return s }
            if let s = fish(size: 3) { return s }
        }
        return nil
    }

    // MARK: Singles

    func nakedSingle() -> Sudoku.Step? {
        for i in 0..<81 where values[i] == 0 && candidates[i].nonzeroBitCount == 1 {
            return Sudoku.Step(technique: .nakedSingle, placement: (i, candidates[i].trailingZeroBitCount))
        }
        return nil
    }

    func hiddenSingle() -> Sudoku.Step? {
        for unit in Self.scanOrder {
            for d in 1...9 {
                let b = Sudoku.bit(d)
                var spot = -1, count = 0
                for i in unit where candidates[i] & b != 0 {
                    spot = i; count += 1
                    if count > 1 { break }
                }
                if count == 1 { return Sudoku.Step(technique: .hiddenSingle, placement: (spot, d)) }
            }
        }
        return nil
    }

    // MARK: Intersections

    func lockedCandidates() -> Sudoku.Step? {
        for d in 1...9 {
            let b = Sudoku.bit(d)
            // Pointing: a box's candidates for d all lie in one row/column.
            for box in Sudoku.boxes {
                var rowBits: UInt16 = 0, colBits: UInt16 = 0, count = 0
                for i in box where candidates[i] & b != 0 {
                    rowBits |= 1 << UInt16(i / 9)
                    colBits |= 1 << UInt16(i % 9)
                    count += 1
                }
                guard count >= 2 else { continue }
                let boxIndex = Sudoku.box(of: box[0])
                if rowBits.nonzeroBitCount == 1 {
                    let line = Sudoku.rows[rowBits.trailingZeroBitCount]
                    if let s = eliminate(b, from: line, except: boxIndex, technique: .lockedCandidates) { return s }
                }
                if colBits.nonzeroBitCount == 1 {
                    let line = Sudoku.columns[colBits.trailingZeroBitCount]
                    if let s = eliminate(b, from: line, except: boxIndex, technique: .lockedCandidates) { return s }
                }
            }
            // Claiming: a line's candidates for d all lie in one box.
            for (n, line) in Self.lines.enumerated() {
                var boxBits: UInt16 = 0, count = 0
                for i in line where candidates[i] & b != 0 {
                    boxBits |= 1 << UInt16(Sudoku.box(of: i))
                    count += 1
                }
                guard count >= 2, boxBits.nonzeroBitCount == 1 else { continue }
                let box = Sudoku.boxes[boxBits.trailingZeroBitCount]
                let isRow = n < 9
                let targets = box.filter { isRow ? $0 / 9 != n : $0 % 9 != n - 9 }
                if let s = eliminate(b, from: targets, technique: .lockedCandidates) { return s }
            }
        }
        return nil
    }

    // MARK: Subsets

    func nakedSubset(size k: Int) -> Sudoku.Step? {
        for unit in Sudoku.allUnits {
            let open = unit.filter { values[$0] == 0 }
            guard open.count > k else { continue }
            let small = open.filter { (2...k).contains(candidates[$0].nonzeroBitCount) }
            for combo in combinations(small, k) {
                let union = combo.reduce(UInt16(0)) { $0 | candidates[$1] }
                guard union.nonzeroBitCount == k else { continue }
                let others = open.filter { !combo.contains($0) }
                let technique: Sudoku.Technique = k == 2 ? .nakedPair : .nakedTriple
                if let s = eliminate(union, from: others, technique: technique) { return s }
            }
        }
        return nil
    }

    func hiddenSubset(size k: Int) -> Sudoku.Step? {
        for unit in Sudoku.allUnits {
            // Positions (as a 9-bit mask over the unit) of each unplaced digit.
            var positions = [UInt16](repeating: 0, count: 10)
            for (p, i) in unit.enumerated() {
                for d in Sudoku.digits(in: candidates[i]) { positions[d] |= 1 << UInt16(p) }
            }
            let digits = (1...9).filter { (2...k).contains(positions[$0].nonzeroBitCount) }
            for combo in combinations(digits, k) {
                let union = combo.reduce(UInt16(0)) { $0 | positions[$1] }
                guard union.nonzeroBitCount == k else { continue }
                let keep = combo.reduce(UInt16(0)) { $0 | Sudoku.bit($1) }
                var elim: [Int: UInt16] = [:]
                for (p, i) in unit.enumerated() where union & (1 << UInt16(p)) != 0 {
                    let extra = candidates[i] & ~keep
                    if extra != 0 { elim[i] = extra }
                }
                if !elim.isEmpty {
                    return Sudoku.Step(technique: k == 2 ? .hiddenPair : .hiddenTriple, eliminations: elim)
                }
            }
        }
        return nil
    }

    // MARK: Fish & wings

    /// X-Wing (size 2) and Swordfish (size 3), on rows and on columns.
    func fish(size k: Int) -> Sudoku.Step? {
        let technique: Sudoku.Technique = k == 2 ? .xWing : .swordfish
        for d in 1...9 {
            let b = Sudoku.bit(d)
            for (bases, covers) in [(Sudoku.rows, Sudoku.columns), (Sudoku.columns, Sudoku.rows)] {
                var masks: [(base: Int, mask: UInt16)] = []
                for (n, line) in bases.enumerated() {
                    var m: UInt16 = 0
                    for (p, i) in line.enumerated() where candidates[i] & b != 0 { m |= 1 << UInt16(p) }
                    if (2...k).contains(m.nonzeroBitCount) { masks.append((n, m)) }
                }
                for combo in combinations(Array(masks.indices), k) {
                    let union = combo.reduce(UInt16(0)) { $0 | masks[$1].mask }
                    guard union.nonzeroBitCount == k else { continue }
                    let baseLines = combo.reduce(UInt16(0)) { $0 | 1 << UInt16(masks[$1].base) }
                    var targets: [Int] = []
                    for c in 0..<9 where union & (1 << UInt16(c)) != 0 {
                        for (p, i) in covers[c].enumerated() where baseLines & (1 << UInt16(p)) == 0 {
                            targets.append(i)
                        }
                    }
                    if let s = eliminate(b, from: targets, technique: technique) { return s }
                }
            }
        }
        return nil
    }

    func xyWing() -> Sudoku.Step? {
        let pairs = (0..<81).filter { values[$0] == 0 && candidates[$0].nonzeroBitCount == 2 }
        for pivot in pairs {
            let pm = candidates[pivot]
            let wings = Sudoku.peers[pivot].filter {
                values[$0] == 0 && candidates[$0].nonzeroBitCount == 2
                    && (candidates[$0] & pm).nonzeroBitCount == 1
            }
            for (x, a) in wings.enumerated() {
                for b in wings[(x + 1)...] {
                    let ma = candidates[a], mb = candidates[b]
                    let shared = ma & mb & ~pm
                    // Pincers {a,c} and {b,c} where {a,b} is the pivot.
                    guard shared.nonzeroBitCount == 1, (ma | mb) & pm == pm, ma != mb else { continue }
                    let targets = Sudoku.peers[a].filter { $0 != b && $0 != pivot && Sudoku.areSeen($0, b) }
                    if let s = eliminate(shared, from: targets, technique: .xyWing) { return s }
                }
            }
        }
        return nil
    }

    // MARK: Helpers

    /// Hidden singles scan boxes first: that's how people usually look.
    private static let scanOrder = Sudoku.boxes + Sudoku.rows + Sudoku.columns
    private static let lines = Sudoku.rows + Sudoku.columns

    private func eliminate(_ mask: UInt16, from line: [Int], except box: Int, technique: Sudoku.Technique) -> Sudoku.Step? {
        var elim: [Int: UInt16] = [:]
        for i in line where Sudoku.box(of: i) != box && candidates[i] & mask != 0 {
            elim[i] = candidates[i] & mask
        }
        return elim.isEmpty ? nil : Sudoku.Step(technique: technique, eliminations: elim)
    }

    private func eliminate(_ mask: UInt16, from cells: [Int], technique: Sudoku.Technique) -> Sudoku.Step? {
        var elim: [Int: UInt16] = [:]
        for i in cells where values[i] == 0 && candidates[i] & mask != 0 {
            elim[i] = candidates[i] & mask
        }
        return elim.isEmpty ? nil : Sudoku.Step(technique: technique, eliminations: elim)
    }

    private func combinations<T>(_ items: [T], _ k: Int) -> [[T]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[T]] = []
        var stack: [Int] = []
        func walk(_ start: Int) {
            if stack.count == k { result.append(stack.map { items[$0] }); return }
            guard start < items.count else { return }
            for i in start..<items.count where items.count - i >= k - stack.count {
                stack.append(i)
                walk(i + 1)
                stack.removeLast()
            }
        }
        walk(0)
        return result
    }
}
