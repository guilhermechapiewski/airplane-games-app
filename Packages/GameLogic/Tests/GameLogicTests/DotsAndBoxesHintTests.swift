import Foundation
import Testing
@testable import GameLogic

@Suite("Dots and Boxes hints")
struct DotsAndBoxesHintTests {
    typealias D = DotsAndBoxes
    typealias Line = D.Line

    /// 2×3 boxes with every horizontal line drawn: two separate chains of three.
    func twoChainsOfThree() -> D.Game {
        let lines = (0...2).flatMap { r in (0..<3).map { Line.h(r, $0) } }
        return D.Game(rows: 2, cols: 3, drawn: lines)
    }

    @Test(arguments: [3, 4, 6])
    func takesAFreeBox(size: Int) throws {
        let game = D.Game(rows: size, cols: size, drawn: [.h(0, 0), .h(1, 0), .v(0, 0)])
        for seed in UInt64(1)...5 {
            let hint = try #require(D.AI.hint(for: game, seed: seed))
            #expect(hint.line == .v(0, 1))
            #expect(hint.kind == .take(boxes: 1))
            #expect(hint.title == "Take this box")
        }
    }

    @Test(arguments: [3, 4, 6])
    func prefersSafeLines(size: Int) throws {
        for seed in UInt64(1)...10 {
            var game = D.Game(rows: size, cols: size)
            var rng = SeededRandom(seed: seed)
            // A few opening moves, still with plenty of safe lines.
            for _ in 0..<size {
                if let line = game.safeLines.randomElement(using: &rng) { game.play(line) }
            }
            let hint = try #require(D.AI.hint(for: game, seed: seed))
            #expect(game.safeLines.contains(hint.line), "seed \(seed): \(hint.line)")
            #expect(hint.kind == .safe)
            #expect(hint.explanation == "It doesn't give away a box.")
        }
    }

    @Test func leavesTheLastTwoBoxesToKeepControl() throws {
        var game = twoChainsOfThree()
        game.play(.v(0, 0)) // one opens the top chain
        let first = try #require(D.AI.hint(for: game, seed: 1))
        #expect(first.line == .v(0, 1))
        #expect(first.kind == .take(boxes: 1))
        game.play(first.line)
        let second = try #require(D.AI.hint(for: game, seed: 1))
        #expect(second.line == .v(0, 3))
        #expect(second.kind == .doubleCross)
        #expect(second.explanation.hasPrefix("Leave the last two boxes to keep control"))
    }

    @Test func givesAwayTheFewestWhenEveryLineCosts() throws {
        // Two chains of three, nothing safe: any opening gives three boxes.
        let hint = try #require(D.AI.hint(for: twoChainsOfThree(), seed: 1))
        #expect(hint.kind == .fewest(boxes: 3))
        #expect(hint.explanation.hasPrefix("Every line gives boxes away — this one gives the fewest"))
    }

    @Test func sacrificesTheLoopToKeepControl() throws {
        // 3×3: a chain of three and a loop of six. Opening the loop first loses less overall.
        let lines: [Line] = [.h(0, 0), .h(0, 1), .h(0, 2), .h(1, 0), .h(1, 1), .h(1, 2),
                             .v(1, 0), .h(2, 1), .v(1, 3), .v(2, 0), .h(3, 0), .h(3, 1), .v(2, 3), .h(3, 2)]
        let hint = try #require(D.AI.hint(for: D.Game(rows: 3, cols: 3, drawn: lines), seed: 1))
        #expect(hint.kind == .sacrifice(boxes: 6))
    }

    @Test func noHintWhenTheGameIsOver() {
        var game = D.Game(rows: 1, cols: 1)
        for line in game.allLines { game.play(line) }
        #expect(D.AI.hint(for: game, seed: 1) == nil)
    }
}
