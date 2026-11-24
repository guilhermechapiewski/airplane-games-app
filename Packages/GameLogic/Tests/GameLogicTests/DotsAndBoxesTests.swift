import Foundation
import Testing
@testable import GameLogic

@Suite("Dots and Boxes")
struct DotsAndBoxesTests {
    typealias D = DotsAndBoxes
    typealias Line = D.Line

    // MARK: Positions

    /// 2×3 boxes with every horizontal line drawn: two separate chains of three.
    func twoChainsOfThree(current: D.Player = .one) -> D.Game {
        let lines = (0...2).flatMap { r in (0..<3).map { Line.h(r, $0) } }
        return D.Game(rows: 2, cols: 3, drawn: lines, current: current)
    }

    /// 3×3 boxes: a chain of three along the top row and a loop of six below it.
    func chainAndLoop() -> D.Game {
        let lines: [Line] = [.h(0, 0), .h(0, 1), .h(0, 2), .h(1, 0), .h(1, 1), .h(1, 2),
                             .v(1, 0), .h(2, 1), .v(1, 3), .v(2, 0), .h(3, 0), .h(3, 1), .v(2, 3), .h(3, 2)]
        return D.Game(rows: 3, cols: 3, drawn: lines)
    }

    /// Plays one full game between two levels; returns the final state.
    func playOut(_ start: D.Game, one: D.Level, two: D.Level, seed: UInt64) -> D.Game {
        var game = start
        var rng = SeededRandom(seed: seed)
        while !game.isOver {
            let level = game.current == .one ? one : two
            let line = D.AI.chooseMove(for: game, level: level, rng: &rng)!
            #expect(game.play(line) != nil, "\(level) played an illegal line \(line)")
        }
        return game
    }

    // MARK: Board

    @Test(arguments: [(3, 24), (4, 40), (6, 84)])
    func lineCounts(size: Int, lines: Int) {
        let game = D.Game(rows: size, cols: size)
        #expect(game.edgeCount == lines)
        #expect(game.availableLines.count == lines)
        #expect(game.boxCount == size * size)
    }

    @Test func lineIndexRoundTrip() {
        let game = D.Game(rows: 4, cols: 6)
        for i in 0..<game.edgeCount {
            let line = game.line(at: i)
            #expect(game.contains(line))
            #expect(game.index(of: line) == i)
        }
        #expect(!game.contains(.h(5, 0)))
        #expect(!game.contains(.v(0, 7)))
        #expect(!game.contains(.h(0, 6)))
    }

    @Test func everyBoxHasFourDistinctSides() {
        let game = D.Game(rows: 3, cols: 3)
        for r in 0..<3 {
            for c in 0..<3 {
                let box = GridPoint(row: r, col: c)
                let sides = game.lines(ofBox: box)
                #expect(Set(sides).count == 4)
                #expect(sides.allSatisfy { game.boxes(adjacentTo: $0).contains(box) })
            }
        }
    }

    // MARK: Rules

    @Test func turnPassesWithoutACompletion() {
        var game = D.Game(rows: 3, cols: 3)
        let turn = game.play(.h(0, 0))
        #expect(turn?.claimed.isEmpty == true)
        #expect(game.current == .two)
        #expect(game.owner(of: .h(0, 0)) == .one)
    }

    @Test func completingABoxClaimsItAndGrantsAnotherMove() {
        var game = D.Game(rows: 3, cols: 3)
        game.play(.h(0, 0)) // one
        game.play(.h(1, 0)) // two
        game.play(.v(0, 0)) // one: box (0,0) now has three sides
        #expect(game.current == .two)
        let turn = game.play(.v(0, 1)) // two completes it
        #expect(turn?.claimed == [GridPoint(row: 0, col: 0)])
        #expect(game.owner(ofBox: GridPoint(row: 0, col: 0)) == .two)
        #expect(game.score(.two) == 1)
        #expect(game.current == .two, "completing a box earns another move")
        game.play(.h(3, 2))
        #expect(game.current == .one)
    }

    @Test func oneLineCanCompleteTwoBoxes() {
        var game = D.Game(rows: 1, cols: 2, drawn: [.h(0, 0), .h(0, 1), .h(1, 0), .h(1, 1), .v(0, 0), .v(0, 2)])
        let turn = game.play(.v(0, 1))
        #expect(turn?.claimed.count == 2)
        #expect(game.score(.one) == 2)
        #expect(game.isOver)
        #expect(game.winner == .one)
    }

    @Test func illegalLinesAreRejected() {
        var game = D.Game(rows: 3, cols: 3)
        game.play(.h(0, 0))
        let before = game
        #expect(game.play(.h(0, 0)) == nil)
        #expect(game.play(.h(4, 0)) == nil)
        #expect(game.play(.v(0, -1)) == nil)
        #expect(game == before)
    }

    @Test func gamesEndWithEveryBoxClaimedAndTiesHappen() {
        var sawTie = false
        for seed in UInt64(1)...60 {
            let game = playOut(D.Game(rows: 2, cols: 2), one: .easy, two: .easy, seed: seed)
            #expect(game.isOver)
            #expect(game.score(.one) + game.score(.two) == 4)
            #expect(game.boxOwners.allSatisfy { $0 != nil })
            if game.score(.one) == game.score(.two) {
                sawTie = true
                #expect(game.isTie)
                #expect(game.winner == nil)
            } else {
                #expect(!game.isTie)
                #expect(game.winner == (game.score(.one) > game.score(.two) ? .one : .two))
            }
        }
        #expect(sawTie)
    }

    @Test func winnerIsNilWhilePlaying() {
        var game = D.Game(rows: 1, cols: 1)
        game.play(.h(0, 0))
        #expect(!game.isOver)
        #expect(game.winner == nil)
        #expect(!game.isTie)
    }

    @Test func undoRestoresEveryEarlierState() {
        var game = D.Game(rows: 3, cols: 3, firstPlayer: .two)
        var states = [game]
        var rng = SeededRandom(seed: 7)
        while !game.isOver {
            game.play(D.AI.chooseMove(for: game, level: .easy, rng: &rng)!)
            states.append(game)
        }
        states.removeLast()
        while let expected = states.popLast() {
            #expect(game.undo() != nil)
            #expect(game == expected)
        }
        #expect(game.undo() == nil)
        #expect(game.current == .two)
    }

    @Test func codableRoundTrip() throws {
        var game = D.Game(rows: 4, cols: 4)
        var rng = SeededRandom(seed: 3)
        for _ in 0..<25 { game.play(D.AI.chooseMove(for: game, level: .medium, rng: &rng)!) }
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(D.Game.self, from: data)
        #expect(decoded == game)
        let level = try JSONDecoder().decode(D.Level.self, from: JSONEncoder().encode(D.Level.hard))
        #expect(level == .hard)
    }

    @Test func safeAndCapturingLines() {
        var game = D.Game(rows: 3, cols: 3)
        #expect(game.safeLines.count == 24)
        game.play(.h(0, 0))
        game.play(.v(0, 0))
        // Box (0,0) has two sides: its other two sides are no longer safe.
        #expect(!game.safeLines.contains(.h(1, 0)))
        #expect(!game.safeLines.contains(.v(0, 1)))
        #expect(game.safeLines.contains(.h(0, 1)))
        #expect(game.capturingLines.isEmpty)
        game.play(.h(1, 0))
        #expect(game.capturingLines == [.v(0, 1)])
    }

    // MARK: Chains

    @Test func detectsChains() {
        let components = twoChainsOfThree().components
        #expect(components.count == 2)
        #expect(components.allSatisfy { $0.kind == .chain && $0.length == 3 && $0.isLong })
        #expect(Set(components.flatMap(\.boxes)).count == 6)
    }

    @Test func detectsLoops() {
        let outer: [Line] = [.h(0, 0), .h(0, 1), .h(2, 0), .h(2, 1), .v(0, 0), .v(1, 0), .v(0, 2), .v(1, 2)]
        let components = D.Game(rows: 2, cols: 2, drawn: outer).components
        #expect(components == [D.Component(kind: .loop, boxes: components[0].boxes)])
        #expect(components[0].length == 4)
    }

    @Test func detectsMixedComponents() {
        let components = chainAndLoop().components
        #expect(components.map(\.kind) == [.loop, .chain])
        #expect(components.map(\.length) == [6, 3])
    }

    @Test func shortChainsAreNotLong() {
        // 1×2 strip with top and bottom drawn: a chain of two.
        let game = D.Game(rows: 1, cols: 2, drawn: [.h(0, 0), .h(0, 1), .h(1, 0), .h(1, 1)])
        #expect(game.components.map(\.length) == [2])
        #expect(game.components[0].isLong == false)
        #expect(D.Game(rows: 3, cols: 3).components.isEmpty)
    }

    // MARK: Endgame values

    @Test func endgameValueOfTwoChains() {
        // Whoever opens first gets 2 of the 6 boxes: the opponent keeps control by double-dealing.
        #expect(D.AI.endgameValue(twoChainsOfThree()) == -2)
    }

    @Test func endgameValueOfChainAndLoop() {
        // Opening the loop first costs 6 but the opponent must then give back the chain: 3 - 6.
        // Opening the chain first lets the opponent double-deal it and then take the loop: 2 - 7.
        #expect(D.AI.endgameValue(chainAndLoop()) == -3)
        #expect(D.AI.endgameValue(D.Game(rows: 3, cols: 3)) == nil, "safe lines remain")
    }

    // MARK: AI

    @Test(arguments: D.Level.allCases)
    func aiOnlyPlaysLegalLines(level: D.Level) {
        for (size, seed) in [(3, UInt64(1)), (4, 2), (6, 3)] {
            let game = playOut(D.Game(rows: size, cols: size), one: level, two: level, seed: seed)
            #expect(game.isOver)
            #expect(game.score(.one) + game.score(.two) == size * size)
        }
    }

    @Test func aiIsDeterministicForASeed() {
        let a = playOut(D.Game(rows: 4, cols: 4), one: .hard, two: .medium, seed: 11)
        let b = playOut(D.Game(rows: 4, cols: 4), one: .hard, two: .medium, seed: 11)
        #expect(a == b)
    }

    @Test(arguments: D.Level.allCases)
    func everyLevelTakesAFreeBox(level: D.Level) {
        // Box (0,0) has three sides; taking it gives nothing away.
        let game = D.Game(rows: 3, cols: 3, drawn: [.h(0, 0), .h(1, 0), .v(0, 0)])
        for seed in UInt64(1)...10 {
            #expect(D.AI.chooseMove(for: game, level: level, seed: seed) == .v(0, 1))
        }
    }

    @Test func mediumNeverOffersABoxWhileSafeLinesRemain() {
        for seed in UInt64(1)...40 {
            var game = D.Game(rows: 4, cols: 4)
            var rng = SeededRandom(seed: seed)
            while !game.isOver {
                let safe = game.safeLines
                let capturing = game.capturingLines
                let line = D.AI.chooseMove(for: game, level: .medium, rng: &rng)!
                if !capturing.isEmpty {
                    #expect(capturing.contains(line))
                } else if !safe.isEmpty {
                    #expect(safe.contains(line))
                }
                game.play(line)
            }
        }
    }

    @Test func mediumGivesAwayTheSmallestRun() {
        let game = chainAndLoop()
        let chainEnds: Set<Line> = [.v(0, 0), .v(0, 1), .v(0, 2), .v(0, 3)]
        for seed in UInt64(1)...10 {
            let line = D.AI.chooseMove(for: game, level: .medium, seed: seed)!
            #expect(chainEnds.contains(line), "the chain of three costs less than the loop of six")
        }
    }

    @Test func mediumTakesTheWholeChain() {
        var game = twoChainsOfThree()
        game.play(.v(0, 0)) // one opens the top chain
        var rng = SeededRandom(seed: 1)
        while game.current == .two {
            game.play(D.AI.chooseMove(for: game, level: .medium, rng: &rng)!)
        }
        #expect(game.score(.two) == 3)
    }

    @Test func hardDoubleDealsToKeepControl() {
        var game = twoChainsOfThree()
        game.play(.v(0, 0)) // one opens the top chain
        var rng = SeededRandom(seed: 1)
        var played: [Line] = []
        while game.current == .two {
            let line = D.AI.chooseMove(for: game, level: .hard, rng: &rng)!
            played.append(line)
            game.play(line)
        }
        // Takes one box, then declines the last two by closing the far end.
        #expect(played == [.v(0, 1), .v(0, 3)])
        #expect(game.score(.two) == 1)
        // The opponent must take the pair and then open the other chain.
        let final = playOut(game, one: .hard, two: .hard, seed: 2)
        #expect(final.score(.two) == 4)
        #expect(final.score(.one) == 2)
    }

    @Test func hardTakesEverythingFromTheLastChain() {
        var game = D.Game(rows: 1, cols: 4, drawn: [.h(0, 0), .h(0, 1), .h(0, 2), .h(0, 3),
                                                    .h(1, 0), .h(1, 1), .h(1, 2), .h(1, 3)])
        game.play(.v(0, 0))
        let final = playOut(game, one: .hard, two: .hard, seed: 1)
        #expect(final.score(.two) == 4)
    }

    @Test func hardOpensTheLoopBeforeTheChain() {
        // Hard opens with the loop; the opponent takes all six and has to open the chain.
        let game = chainAndLoop()
        let first = D.AI.chooseMove(for: game, level: .hard, seed: 1)!
        let chainLines: Set<Line> = [.v(0, 0), .v(0, 1), .v(0, 2), .v(0, 3)]
        #expect(!chainLines.contains(first), "opening the loop first loses less")
        let final = playOut(game, one: .hard, two: .hard, seed: 1)
        #expect(final.score(.one) == 3)
        #expect(final.score(.two) == 6)
    }

    @Test func hardOpensATwoChainInTheMiddle() {
        // Opening a chain of two in the middle stops the opponent from declining it.
        let pair = D.Game(rows: 1, cols: 2, drawn: [.h(0, 0), .h(0, 1), .h(1, 0), .h(1, 1)])
        #expect(D.AI.chooseMove(for: pair, level: .hard, seed: 1) == .v(0, 1))
    }

    @Test func hardBeatsMedium() {
        var hardWins = 0, mediumWins = 0
        let games = 20
        for seed in UInt64(1)...UInt64(games) {
            let hardFirst = seed % 2 == 0
            let start = D.Game(rows: 4, cols: 4)
            let final = playOut(start, one: hardFirst ? .hard : .medium, two: hardFirst ? .medium : .hard, seed: seed)
            let hard: D.Player = hardFirst ? .one : .two
            if final.winner == hard { hardWins += 1 } else if final.winner == hard.other { mediumWins += 1 }
        }
        #expect(hardWins >= games * 3 / 4, "Hard won \(hardWins), Medium \(mediumWins) of \(games)")
    }

    @Test func mediumBeatsEasy() {
        var mediumWins = 0
        for seed in UInt64(1)...20 {
            let mediumFirst = seed % 2 == 0
            let final = playOut(D.Game(rows: 4, cols: 4), one: mediumFirst ? .medium : .easy,
                                two: mediumFirst ? .easy : .medium, seed: seed)
            if final.winner == (mediumFirst ? .one : .two) { mediumWins += 1 }
        }
        #expect(mediumWins >= 15)
    }

    @Test func hardMovesAreQuickOnTheBigBoard() {
        var game = D.Game(rows: 6, cols: 6)
        var rng = SeededRandom(seed: 5)
        var slowest: Duration = .zero
        let clock = ContinuousClock()
        while !game.isOver {
            let start = clock.now
            let line = D.AI.chooseMove(for: game, level: .hard, rng: &rng)!
            slowest = max(slowest, clock.now - start)
            game.play(line)
        }
        #expect(slowest < .seconds(1.5), "slowest Hard move took \(slowest)")
    }
}
