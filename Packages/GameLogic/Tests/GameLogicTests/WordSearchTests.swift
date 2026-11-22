import Foundation
import Testing
@testable import GameLogic

@Suite("Word Search")
struct WordSearchTests {
    typealias W = WordSearch

    private func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }

    @Test func linesOnlyInEightDirections() {
        #expect(W.line(from: p(0, 0), to: p(0, 3)) == [p(0, 0), p(0, 1), p(0, 2), p(0, 3)])
        #expect(W.line(from: p(3, 3), to: p(0, 0)) == [p(3, 3), p(2, 2), p(1, 1), p(0, 0)])
        #expect(W.line(from: p(2, 0), to: p(0, 2)) == [p(2, 0), p(1, 1), p(0, 2)])
        #expect(W.line(from: p(0, 0), to: p(1, 2)) == nil)
        #expect(W.line(from: p(1, 1), to: p(1, 1)) == [p(1, 1)])
    }

    @Test func snappingPicksNearestDirectionAndClamps() {
        #expect(W.snappedEnd(from: p(0, 0), toward: (row: 0.3, col: 4.2), size: 8) == p(0, 4))
        #expect(W.snappedEnd(from: p(0, 0), toward: (row: 3.1, col: 2.8), size: 8) == p(3, 3))
        #expect(W.snappedEnd(from: p(5, 5), toward: (row: 5.2, col: 1.1), size: 8) == p(5, 1))
        #expect(W.snappedEnd(from: p(5, 5), toward: (row: 1.0, col: 5.4), size: 8) == p(1, 5))
        #expect(W.snappedEnd(from: p(2, 2), toward: (row: -4, col: -4), size: 8) == p(0, 0))
        #expect(W.snappedEnd(from: p(2, 2), toward: (row: 2.2, col: 2.1), size: 8) == p(2, 2))
        #expect(W.snappedEnd(from: p(6, 1), toward: (row: 2, col: 5), size: 8) == p(2, 5))
    }

    @Test func settingsPerDifficulty() {
        #expect(W.settings(for: .easy).size == 8)
        #expect(W.settings(for: .easy).directions.count == 2)
        #expect(W.settings(for: .medium).size == 10)
        #expect(W.settings(for: .medium).directions.count == 4)
        #expect(W.settings(for: .hard).size == 12)
        #expect(W.settings(for: .hard).directions.count == 8)
    }

    @Test func chosenWordsNeverContainEachOther() {
        var rng = SeededRandom(seed: 5)
        let pool = ["ant", "antelope", "pole", "elope", "cat", "tac", "dog", "bird", "fish", "god"]
        for _ in 0..<50 {
            let words = W.chooseWords(from: pool, count: 6, size: 10, using: &rng)
            for a in words {
                for b in words where a != b {
                    #expect(!a.contains(b) && !a.contains(String(b.reversed())), "\(a) contains \(b)")
                }
            }
        }
    }

    @Test(arguments: [Difficulty.easy, .medium, .hard])
    func generatorPlacesAllWordsExactlyOnceOverManySeeds(_ difficulty: Difficulty) {
        let settings = W.settings(for: difficulty)
        let allowed = Set(settings.directions)
        for seed in UInt64(0)..<60 {
            var rng = SeededRandom(seed: seed)
            let category = WordCategory.all[Int(seed) % WordCategory.all.count]
            let puzzle = W.generate(category: category, difficulty: difficulty, using: &rng)
            #expect(puzzle.size == settings.size)
            #expect(puzzle.cells.count == settings.size * settings.size)
            #expect(puzzle.placements.count == settings.wordCount, "\(category.id) seed \(seed)")
            #expect(puzzle.title == category.title)
            #expect(puzzle.cells.allSatisfy { $0.count == 1 && ("a"..."z").contains($0) })
            for placement in puzzle.placements {
                #expect(allowed.contains(placement.step))
                #expect(placement.cells.allSatisfy { $0.isInside(rows: puzzle.size, cols: puzzle.size) })
                #expect(puzzle.text(along: placement.cells) == placement.word)
                #expect(puzzle.occurrences(of: placement.word) == 1, "\(placement.word) duplicated, seed \(seed)")
                #expect(category.entries.contains(placement.word))
                #expect(WordLists.isClean(placement.word))
            }
            #expect(Set(puzzle.words).count == puzzle.words.count)
            #expect(puzzle.lines(maxLength: puzzle.size).isDisjoint(with: WordLists.blocklist))
        }
    }

    @Test func generationIsDeterministic() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        let category = WordCategory.named("ocean")!
        #expect(W.generate(category: category, difficulty: .hard, using: &a)
                == W.generate(category: category, difficulty: .hard, using: &b))
    }

    @Test func everyCategoryWorksOnEveryDifficulty() {
        var rng = SeededRandom(seed: 11)
        for category in WordCategory.all {
            for d in [Difficulty.easy, .medium, .hard] {
                let puzzle = W.generate(category: category, difficulty: d, using: &rng)
                #expect(puzzle.placements.count == W.settings(for: d).wordCount, "\(category.id) \(d)")
            }
        }
    }

    @Test func impossibleRequestReturnsNil() {
        var rng = SeededRandom(seed: 1)
        #expect(W.generate(words: ["elephants"], size: 5, directions: W.allDirections, title: "", using: &rng) == nil)
    }

    @Test func selectionWorksInBothDirections() throws {
        var rng = SeededRandom(seed: 9)
        let puzzle = W.generate(category: WordCategory.named("animals")!, difficulty: .hard, using: &rng)
        var state = W.State(puzzle: puzzle, difficulty: .hard)
        let first = puzzle.placements[0], second = puzzle.placements[1]
        let s1 = state.select(from: first.start, to: first.end)
        #expect(s1 == .found(0))
        let s2 = state.select(from: first.end, to: first.start)
        #expect(s2 == .alreadyFound(0))
        let s3 = state.select(from: second.end, to: second.start)
        #expect(s3 == .found(1))
        // A partial selection is not a word.
        let s4 = state.select(from: puzzle.placements[2].start, to: puzzle.placements[2].start)
        #expect(s4 == .miss)
        let cells = puzzle.placements[2].cells
        let s5 = state.select(from: cells[0], to: cells[cells.count - 2])
        #expect(s5 == .miss)
        #expect(state.found == [0, 1])
        #expect(!state.isComplete)
        for (i, p) in puzzle.placements.enumerated() { _ = state.select(from: p.start, to: p.end); _ = i }
        #expect(state.isComplete)
        #expect(state.remaining.isEmpty)
    }

    @Test func hintsTargetRemainingWords() {
        var rng = SeededRandom(seed: 3)
        let puzzle = W.generate(category: WordCategory.named("food")!, difficulty: .easy, using: &rng)
        var state = W.State(puzzle: puzzle, difficulty: .easy)
        _ = state.select(from: puzzle.placements[0].start, to: puzzle.placements[0].end)
        let s6 = state.useHint()
        #expect(s6 == 1)
        #expect(state.hintsUsed == 1)
    }

    @Test func codableRoundTrip() throws {
        var rng = SeededRandom(seed: 21)
        let puzzle = W.generate(category: WordCategory.named("space")!, difficulty: .medium, using: &rng)
        var state = W.State(puzzle: puzzle, difficulty: .medium)
        _ = state.select(from: puzzle.placements[0].start, to: puzzle.placements[0].end)
        let back = try JSONDecoder().decode(W.State.self, from: JSONEncoder().encode(state))
        #expect(back == state)
    }
}
