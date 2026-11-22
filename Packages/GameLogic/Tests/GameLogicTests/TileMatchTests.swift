import Foundation
import Testing
@testable import GameLogic

@Suite("Tile Match")
struct TileMatchTests {
    typealias T = TileMatch
    typealias P = TileMatch.Position

    func pos(_ x: Int, _ y: Int, _ z: Int = 0) -> P { P(x: x, y: y, z: z) }

    /// Replays a removal sequence; returns true if every step is legal and the board ends empty.
    func replay(_ state: T.State, _ order: [T.Pair]) -> Bool {
        var s = state
        for pair in order {
            guard s.match(pair.a, pair.b) else { return false }
        }
        return s.isCleared
    }

    // MARK: Layouts

    @Test(arguments: T.LayoutID.allCases)
    func layoutIsValid(_ id: T.LayoutID) {
        let layout = id.layout
        let all = Set(layout.positions)
        #expect(all.count == layout.positions.count, "duplicate slots")
        #expect(layout.tileCount.isMultiple(of: 2))
        #expect(layout.tileCount >= 36 && layout.tileCount <= 144)
        // No two tiles in the same layer overlap.
        let byLayer = Dictionary(grouping: layout.positions, by: \.z)
        for (_, layer) in byLayer {
            for i in layer.indices {
                for j in layer.indices where j > i {
                    #expect(!layer[i].overlapsFootprint(of: layer[j]), "overlap \(layer[i]) \(layer[j])")
                }
            }
        }
        // Every half-cell of an upper tile rests on a tile in the layer below.
        for p in layout.positions where p.z > 0 {
            let below = byLayer[p.z - 1] ?? []
            for cx in p.x..<(p.x + 2) {
                for cy in p.y..<(p.y + 2) {
                    let supported = below.contains { $0.x <= cx && cx < $0.x + 2 && $0.y <= cy && cy < $0.y + 2 }
                    #expect(supported, "\(id): \(p) unsupported at (\(cx),\(cy))")
                }
            }
        }
    }

    @Test func layoutSizesCoverPhoneAndTablet() {
        let counts = T.LayoutID.allCases.map(\.layout.tileCount)
        #expect(counts == counts.sorted(), "layouts are listed smallest first")
        #expect(counts.first! <= 72)
        #expect(counts.last! == 144)
        #expect(T.LayoutID.pebble.layout.tileCount == 36)
    }

    // MARK: Free rule

    @Test func tileWithOpenSideIsFree() {
        let row: Set<P> = [pos(0, 0), pos(2, 0), pos(4, 0)]
        #expect(T.isFree(pos(0, 0), in: row))
        #expect(!T.isFree(pos(2, 0), in: row))
        #expect(T.isFree(pos(4, 0), in: row))
    }

    @Test func halfOffsetNeighbourBlocksSide() {
        // A tile half a row lower still touches the side.
        let s: Set<P> = [pos(0, 1), pos(2, 0), pos(4, 1)]
        #expect(!T.isFree(pos(2, 0), in: s))
        // A full row lower does not touch.
        let t: Set<P> = [pos(0, 2), pos(2, 0), pos(4, 2)]
        #expect(T.isFree(pos(2, 0), in: t))
    }

    @Test func tileUnderneathIsBlockedEvenByPartialOverlap() {
        #expect(!T.isFree(pos(0, 0), in: [pos(0, 0), pos(0, 0, 1)]))
        #expect(!T.isFree(pos(0, 0), in: [pos(0, 0), pos(1, 1, 1)]))
        #expect(T.isFree(pos(0, 0), in: [pos(0, 0), pos(2, 0, 1)]))
        // A tile two layers up does not count directly.
        #expect(T.isFree(pos(0, 0), in: [pos(0, 0), pos(0, 0, 2)]))
    }

    // MARK: Faces

    @Test func faceMatching() {
        #expect(T.Face(.ocean, 3).matches(T.Face(.ocean, 3)))
        #expect(!T.Face(.ocean, 3).matches(T.Face(.ocean, 4)))
        #expect(!T.Face(.ocean, 3).matches(T.Face(.forest, 3)))
        #expect(T.Face(.weather, 2).matches(T.Face(.weather, 2)))
        #expect(!T.Face(.weather, 2).matches(T.Face(.weather, 1)))
        #expect(T.Face(.treasure, 1).matches(T.Face(.treasure, 4)))
        #expect(T.Face(.critter, 2).matches(T.Face(.critter, 3)))
        #expect(!T.Face(.critter, 2).matches(T.Face(.treasure, 2)))
        #expect(T.Face.all.count == 42)
    }

    @Test func fullSetHasClassicComposition() {
        var rng = SeededRandom(seed: 9)
        let pairs = T.facePairs(count: 144, using: &rng)
        #expect(pairs.count == 72)
        #expect(pairs.allSatisfy { $0.0.matches($0.1) })
        var counts: [T.Face: Int] = [:]
        for p in pairs { counts[p.0, default: 0] += 1; counts[p.1, default: 0] += 1 }
        for face in T.Face.all {
            #expect(counts[face] == (face.suit.isBonus ? 1 : 4), "\(face)")
        }
    }

    @Test(arguments: [36, 66, 82, 104, 134])
    func smallerSetsUseMatchingGroups(_ count: Int) {
        var rng = SeededRandom(seed: UInt64(count))
        let pairs = T.facePairs(count: count, using: &rng)
        #expect(pairs.count == count / 2)
        #expect(pairs.allSatisfy { $0.0.matches($0.1) })
        var counts: [T.Face: Int] = [:]
        for p in pairs { counts[p.0.matchKey, default: 0] += 2 }
        #expect(counts.values.allSatisfy { $0 <= 4 })
    }

    // MARK: Generation

    @Test(arguments: T.LayoutID.allCases)
    func dealsAreSolvableByReplayingConstruction(_ id: T.LayoutID) {
        for seed in UInt64(0)..<40 {
            let s = T.State.newGame(layout: id, seed: seed)
            #expect(s.tiles.count == id.layout.tileCount)
            #expect(Set(s.tiles.map(\.position)) == Set(id.layout.positions))
            #expect(Set(s.tiles.map(\.id)).count == s.tiles.count)
            #expect(s.solution.count == s.tiles.count / 2)
            #expect(replay(s, s.solution), "\(id) seed \(seed) not solvable by its construction")
            #expect(s.hasMoves)
        }
    }

    @Test func generationIsDeterministic() {
        let a = T.State.newGame(layout: .butterfly, seed: 42)
        let b = T.State.newGame(layout: .butterfly, seed: 42)
        let c = T.State.newGame(layout: .butterfly, seed: 43)
        #expect(a == b)
        #expect(a.tiles != c.tiles)
    }

    @Test func generationIsFast() {
        let start = threadCPUTime()
        _ = T.State.newGame(layout: .fortress, seed: 7)
        // Generous bound for debug builds on CI; typically a few milliseconds.
        #expect(threadCPUTime() - start < 0.5)
    }

    // MARK: Moves

    /// Three free tiles in a row: ocean1, ocean1, forest2 — plus a covered ocean1.
    func smallState() -> T.State {
        T.State(layout: .pebble, tiles: [
            T.Tile(id: 0, face: T.Face(.ocean, 1), position: pos(0, 0)),
            T.Tile(id: 1, face: T.Face(.forest, 2), position: pos(2, 0)),
            T.Tile(id: 2, face: T.Face(.ocean, 1), position: pos(4, 0)),
            T.Tile(id: 3, face: T.Face(.forest, 2), position: pos(2, 0, 1)),
        ])
    }

    @Test func matchRequiresFreeMatchingTiles() {
        var s = smallState()
        #expect(s.freeTileIDs == [0, 2, 3])
        let r1 = s.match(0, 1)
        #expect(!r1, "1 is covered")
        let r2 = s.match(0, 3)
        #expect(!r2, "faces differ")
        let r3 = s.match(0, 0)
        #expect(!r3, "same tile")
        let r4 = s.match(0, 99)
        #expect(!r4, "missing tile")
        #expect(s.tiles.count == 4)
        let r5 = s.match(0, 2)
        #expect(r5)
        #expect(s.tiles.map(\.id).sorted() == [1, 3])
        #expect(s.isFree(1) == false)
        #expect(s.matchesMade == 1)
    }

    @Test func undoRestoresTiles() {
        var s = smallState()
        let original = s.tiles
        s.match(0, 2)
        let r6 = s.undo()
        #expect(r6 != nil)
        #expect(s.tiles == original)
        #expect(s.history.isEmpty)
        let r7 = s.undo()
        #expect(r7 == nil)
    }

    @Test func noMovesDetected() {
        // Two matching tiles stacked: the lower one can never be free.
        let s = T.State(layout: .pebble, tiles: [
            T.Tile(id: 0, face: T.Face(.ember, 5), position: pos(0, 0)),
            T.Tile(id: 1, face: T.Face(.ember, 5), position: pos(0, 0, 1)),
        ])
        #expect(!s.hasMoves)
        #expect(s.hint() == nil)
        var t = s
        let r8 = t.shuffle()
        #expect(r8 == .impossible)
        #expect(t.tiles == s.tiles && t.history.isEmpty && t.shuffleCount == 0)
    }

    @Test func hintFindsFreeMatchingPair() {
        let s = smallState()
        let h = s.hint()
        #expect(h != nil)
        if let h { #expect(s.canMatch(h.a, h.b)) }
    }

    @Test func hintFollowsSolutionAndCanFinishAGame() {
        var s = T.State.newGame(layout: .lantern, seed: 5)
        var steps = 0
        while let h = s.hint() {
            let r9 = s.match(h.a, h.b)
            #expect(r9)
            steps += 1
        }
        #expect(s.isCleared)
        #expect(steps == 33)
    }

    @Test func hintRecoversAfterDeviation() {
        // Play random legal moves, then the hint should still find a pair whenever one exists.
        var s = T.State.newGame(layout: .pebble, seed: 11)
        var rng = SeededRandom(seed: 3)
        for _ in 0..<5 {
            guard let m = s.availableMatches.randomElement(using: &rng) else { break }
            s.match(m.a, m.b)
        }
        #expect((s.hint() != nil) == s.hasMoves)
    }

    @Test func solverClearsDeals() {
        for id in [T.LayoutID.pebble, .lantern, .pyramid] {
            let s = T.State.newGame(layout: id, seed: 21)
            let path = T.solve(tiles: s.tiles, budget: 20000)
            #expect(path != nil, "\(id)")
            if let path { #expect(replay(s, path)) }
        }
    }

    // MARK: Shuffle

    @Test func shuffleKeepsTilesAndSlotsAndStaysSolvable() {
        for seed in UInt64(0)..<10 {
            var s = T.State.newGame(layout: .bridge, seed: seed)
            var rng = SeededRandom(seed: seed)
            for _ in 0..<10 {
                guard let m = s.availableMatches.randomElement(using: &rng) else { break }
                s.match(m.a, m.b)
            }
            let before = s
            let result = s.shuffle()
            #expect(result != .impossible)
            #expect(Set(s.tiles.map(\.position)) == Set(before.tiles.map(\.position)))
            #expect(s.tiles.map(\.id).sorted() == before.tiles.map(\.id).sorted())
            for t in s.tiles { #expect(before.tile(t.id)?.face == t.face, "faces travel with their tile") }
            #expect(s.shuffleCount == 1)
            if result == .solvable { #expect(replay(s, s.solution)) }
        }
    }

    @Test func undoShuffleRestoresArrangement() {
        var s = T.State.newGame(layout: .pebble, seed: 2)
        let h = s.hint()!
        s.match(h.a, h.b)
        let before = s
        s.shuffle()
        #expect(s.tiles != before.tiles)
        guard case .shuffle = s.undo() else {
            Issue.record("expected shuffle undo")
            return
        }
        #expect(s.tiles == before.tiles)
        #expect(s.solution == before.solution)
        #expect(s.shuffleCount == 0)
        #expect(s.matchesMade == 1)
    }

    @Test func shuffleRescuesAStuckBoard() {
        // Two pairs where each matching tile hides under the other pair: no moves until shuffled.
        let tiles = [
            T.Tile(id: 0, face: T.Face(.charm, 1), position: pos(0, 0)),
            T.Tile(id: 1, face: T.Face(.charm, 2), position: pos(0, 0, 1)),
            T.Tile(id: 2, face: T.Face(.charm, 2), position: pos(4, 0)),
            T.Tile(id: 3, face: T.Face(.charm, 1), position: pos(4, 0, 1)),
        ]
        var s = T.State(layout: .pebble, tiles: tiles)
        #expect(!s.hasMoves)
        let r10 = s.shuffle()
        #expect(r10 == .solvable)
        #expect(s.hasMoves)
        #expect(replay(s, s.solution))
    }

    // MARK: Persistence

    @Test func codableRoundTrip() throws {
        var s = T.State.newGame(layout: .pyramid, seed: 77)
        let h = s.hint()!
        s.match(h.a, h.b)
        s.shuffle()
        let data = try JSONEncoder().encode(s)
        var decoded = try JSONDecoder().decode(T.State.self, from: data)
        #expect(decoded == s)
        // The RNG state survives too, so the next shuffle is identical.
        var original = s
        original.shuffle()
        decoded.shuffle()
        #expect(decoded == original)
    }
}

extension TileMatchTests {
    @Test func hintStaysQuickOffTheKnownPath() {
        var s = T.State.newGame(layout: .fortress, seed: 99)
        var rng = SeededRandom(seed: 99)
        for _ in 0..<12 {
            guard let m = s.availableMatches.randomElement(using: &rng) else { break }
            s.match(m.a, m.b)
        }
        let start = Date()
        let h = s.hint()
        #expect(Date().timeIntervalSince(start) < 1.0)
        #expect((h != nil) == s.hasMoves)
    }
}
