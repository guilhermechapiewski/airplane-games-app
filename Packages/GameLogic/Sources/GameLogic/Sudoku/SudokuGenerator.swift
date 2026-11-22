extension Sudoku {
    /// A generated puzzle together with its unique solution.
    public struct Puzzle: Codable, Equatable, Sendable {
        /// Row-major givens, 0 = empty.
        public let givens: [Int]
        public let solution: [Int]
        public let difficulty: Difficulty
        /// Hardest technique a logical solver needs.
        public let hardestTechnique: Technique?

        public init(givens: [Int], solution: [Int], difficulty: Difficulty, hardestTechnique: Technique? = nil) {
            self.givens = givens
            self.solution = solution
            self.difficulty = difficulty
            self.hardestTechnique = hardestTechnique
        }

        public var clueCount: Int { givens.filter { $0 != 0 }.count }
    }

    /// Generation targets for each difficulty.
    struct Profile {
        /// Hardest technique level the puzzle may require while digging.
        let maxLevel: Int
        /// Digging stops once the clue count reaches this.
        let minClues: Int
        /// Whether a finished dig is a good representative of the difficulty.
        let accepts: (_ grade: Grade, _ clues: Int) -> Bool

        static func `for`(_ difficulty: Difficulty) -> Profile {
            switch difficulty {
            case .easy:
                Profile(maxLevel: 1, minClues: 36) { g, clues in g.level == 1 && clues <= 44 }
            case .medium:
                Profile(maxLevel: 2, minClues: 30) { g, clues in g.level == 2 && clues <= 34 }
            case .hard:
                Profile(maxLevel: 3, minClues: 25) { g, clues in g.level == 3 && clues <= 30 }
            case .expert:
                Profile(maxLevel: 4, minClues: 22) { g, clues in g.level == 4 && clues <= 27 }
            }
        }
    }

    /// Generates a puzzle with a unique solution graded at `difficulty`.
    ///
    /// Clues are removed in symmetric pairs (180° rotation) as long as the puzzle stays
    /// uniquely solvable *and* solvable with the techniques allowed for the difficulty.
    /// Deterministic for a given seed.
    public static func generate(difficulty: Difficulty, seed: UInt64) -> Puzzle {
        var rng = SeededRandom(seed: seed)
        let profile = Profile.for(difficulty)
        var fallback: (puzzle: Puzzle, score: Int)?

        for _ in 0..<120 {
            let solution = randomSolution(using: &rng)
            let (givens, grade) = dig(solution, profile: profile, rng: &rng)
            let clues = givens.filter { $0 != 0 }.count
            let puzzle = Puzzle(givens: givens, solution: solution, difficulty: difficulty,
                                hardestTechnique: grade.hardest)
            if profile.accepts(grade, clues) { return puzzle }
            // Prefer the hardest grade, then the fewest clues.
            let score = grade.level * 100 - clues
            if grade.solved, score > (fallback?.score ?? .min) { fallback = (puzzle, score) }
        }
        return fallback!.puzzle
    }

    static func dig(_ solution: [Int], profile: Profile, rng: inout SeededRandom) -> ([Int], Grade) {
        var grid = solution
        var clues = cellCount
        for cell in Array(0...40).shuffled(using: &rng) {
            let mirror = cellCount - 1 - cell
            let removing = cell == mirror ? 1 : 2
            guard clues - removing >= profile.minClues else { continue }
            grid[cell] = 0
            grid[mirror] = 0
            // While many clues remain, a unique grid is virtually always solvable with
            // singles, so the (slower) logical grading is skipped for the harder levels.
            let needsGrade = profile.maxLevel < 3 || clues - removing < 40
            if hasUniqueSolution(grid) && (!needsGrade || grade(grid, maxLevel: profile.maxLevel).solved) {
                clues -= removing
            } else {
                grid[cell] = solution[cell]
                grid[mirror] = solution[mirror]
            }
        }
        return (grid, grade(grid, maxLevel: profile.maxLevel))
    }
}
