import Testing
@testable import GameLogic

@Suite("Core")
struct CoreTests {
    @Test func seededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
    }

    @Test func differentSeedsDiverge() {
        var a = SeededRandom(seed: 1)
        var b = SeededRandom(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test func seededRandomWorksWithShuffle() {
        var r1 = SeededRandom(seed: 7)
        var r2 = SeededRandom(seed: 7)
        #expect(Array(0..<50).shuffled(using: &r1) == Array(0..<50).shuffled(using: &r2))
    }

    @Test func stableSeedIsAFixedValue() {
        // FNV-1a; never change it, it would change everyone's seeded levels.
        #expect(SeededRandom.stableSeed("") == 0xcbf2_9ce4_8422_2325)
        #expect(SeededRandom.stableSeed("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func gridPointBounds() {
        #expect(GridPoint(row: 0, col: 0).isInside(rows: 3, cols: 3))
        #expect(!GridPoint(row: 3, col: 0).isInside(rows: 3, cols: 3))
        #expect(!GridPoint(row: 0, col: -1).isInside(rows: 3, cols: 3))
        #expect(GridPoint.neighborOffsets.count == 8)
    }

    @Test func directionOpposites() {
        for d in Direction.allCases {
            #expect(d.opposite.opposite == d)
            #expect(d.offset + d.opposite.offset == GridPoint(row: 0, col: 0))
        }
    }
}
