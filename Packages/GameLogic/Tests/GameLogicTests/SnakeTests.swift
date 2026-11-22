import Foundation
import Testing
@testable import GameLogic

@Suite("Snake")
struct SnakeTests {
    typealias S = Snake

    private func p(_ r: Int, _ c: Int) -> GridPoint { GridPoint(row: r, col: c) }

    /// A horizontal snake heading right with its head at (row, col).
    private func state(head: GridPoint = GridPoint(row: 2, col: 3), length: Int = 3, food: GridPoint? = nil,
                       size: Int = 6, mode: S.WallMode = .walls) -> S.State {
        let body = (0..<length).map { GridPoint(row: head.row, col: head.col - $0) }
        return S.State(width: size, height: size, wallMode: mode, body: body, direction: .right, food: food, seed: 1)
    }

    // MARK: New game

    @Test func newGameSetup() {
        let s = S.State.newGame(seed: 3)
        #expect(s.width == S.defaultSize && s.height == S.defaultSize)
        #expect(s.length == S.startLength)
        #expect(s.direction == .right)
        #expect(s.status == .playing)
        #expect(s.score == 0)
        #expect(s.head == p(7, 5))
        #expect(s.body == [p(7, 5), p(7, 4), p(7, 3)])
        let food = try! #require(s.food)
        #expect(!s.body.contains(food))
        #expect(food.isInside(rows: s.height, cols: s.width))
    }

    @Test func newGameIsDeterministic() {
        #expect(S.State.newGame(seed: 11) == S.State.newGame(seed: 11))
        let foods = Set((0..<30).compactMap { S.State.newGame(seed: UInt64($0)).food })
        #expect(foods.count > 10)
    }

    // MARK: Movement

    @Test func tickMovesForward() {
        var s = state(food: p(5, 5))
        let r = s.tick()
        #expect(r == S.TickResult())
        #expect(s.body == [p(2, 4), p(2, 3), p(2, 2)])
        #expect(s.ticks == 1)
    }

    @Test func turnAppliesOnNextTick() {
        var s = state(food: p(5, 5))
        do { let v = s.turn(.down); #expect(v) }
        #expect(s.direction == .right)
        #expect(s.nextDirection == .down)
        s.tick()
        #expect(s.head == p(3, 3))
        #expect(s.direction == .down)
    }

    @Test func reversingIsIgnored() {
        var s = state(food: p(5, 5))
        do { let v = s.turn(.left); #expect(!v) }
        do { let v = s.turn(.right); #expect(!v) } // same direction
        s.tick()
        #expect(s.head == p(2, 4))
    }

    @Test func queueBuffersTwoTurnsAndChecksAgainstLastQueued() {
        var s = state(head: p(2, 3), food: p(5, 0))
        do { let v = s.turn(.up); #expect(v) }
        do { let v = s.turn(.down); #expect(!v) }   // reverse of the queued "up"
        do { let v = s.turn(.left); #expect(v) }    // valid after "up" even though it reverses the current "right"
        do { let v = s.turn(.down); #expect(!v) }   // buffer full
        #expect(s.queue == [.up, .left])
        s.tick()
        #expect(s.head == p(1, 3))
        s.tick()
        #expect(s.head == p(1, 2))
        #expect(s.queue.isEmpty)
    }

    @Test func quickUTurnDoesNotKillTheSnake() {
        // Up then left within one tick must not reverse straight into the neck.
        var s = state(head: p(3, 3), food: p(0, 0))
        s.turn(.up)
        s.turn(.left)
        do { let v = s.tick(); #expect(v.died == nil) }
        do { let v = s.tick(); #expect(v.died == nil) }
        #expect(s.body == [p(2, 2), p(2, 3), p(3, 3)])
    }

    // MARK: Eating

    @Test func eatingGrowsAndScoresAndRespawnsFood() {
        var s = state(head: p(2, 3), food: p(2, 4))
        let r = s.tick()
        #expect(r.ate)
        #expect(s.score == 1)
        #expect(s.length == 4)
        #expect(s.body == [p(2, 4), p(2, 3), p(2, 2), p(2, 1)])
        let food = try! #require(s.food)
        #expect(!s.body.contains(food))
    }

    @Test func foodNeverSpawnsOnSnake() {
        for seed in UInt64(0)..<100 {
            var s = S.State.newGame(width: 5, height: 5, seed: seed)
            var guardCount = 0
            while !s.isOver && guardCount < 500 {
                // Steer greedily toward the food.
                if let f = s.food {
                    let h = s.head
                    let want: Direction = f.row < h.row ? .up : f.row > h.row ? .down : f.col < h.col ? .left : .right
                    s.turn(want)
                    #expect(!s.body.contains(f))
                }
                s.tick()
                guardCount += 1
            }
            #expect(s.isOver)
        }
    }

    // MARK: Collisions

    @Test func hittingWallEndsGame() {
        var s = state(head: p(2, 5), food: p(0, 0))
        let r = s.tick()
        #expect(r.died == .wall)
        #expect(s.status == .lost)
        #expect(s.deathCause == .wall)
        #expect(s.head == p(2, 5)) // body unchanged on death
        // Further ticks and turns do nothing.
        do { let v = s.tick(); #expect(v == S.TickResult()) }
        do { let v = s.turn(.up); #expect(!v) }
    }

    @Test func wallsOnEveryEdge() {
        for (dir, head) in [(Direction.up, p(0, 3)), (.down, p(5, 3)), (.left, p(3, 0))] {
            var s = S.State(width: 6, height: 6, wallMode: .walls, body: [head], direction: dir, food: p(3, 3), seed: 1)
            do { let v = s.tick(); #expect(v.died == .wall, "\(dir)") }
        }
    }

    @Test func wrapModePassesThroughEdges() {
        var s = state(head: p(2, 5), food: p(0, 0), mode: .wrap)
        let r = s.tick()
        #expect(r.died == nil)
        #expect(r.wrapped)
        #expect(s.head == p(2, 0))
        var up = S.State(width: 6, height: 6, wallMode: .wrap, body: [p(0, 2)], direction: .up, food: p(3, 3), seed: 1)
        up.tick()
        #expect(up.head == p(5, 2))
        var left = S.State(width: 6, height: 6, wallMode: .wrap, body: [p(1, 0)], direction: .left, food: p(3, 3), seed: 1)
        left.tick()
        #expect(left.head == p(1, 5))
        var down = S.State(width: 6, height: 6, wallMode: .wrap, body: [p(5, 1)], direction: .down, food: p(3, 3), seed: 1)
        down.tick()
        #expect(down.head == p(0, 1))
    }

    @Test func bitingOwnBodyEndsGame() {
        // Head at (2,2) heading left; body loops so (2,1) is occupied by a middle segment.
        let body = [p(2, 2), p(3, 2), p(3, 1), p(2, 1), p(1, 1), p(1, 0)]
        var s = S.State(width: 6, height: 6, wallMode: .walls, body: body, direction: .up, food: p(5, 5), seed: 1)
        s.turn(.left)
        let r = s.tick()
        #expect(r.died == .selfCollision)
        #expect(s.deathCause == .selfCollision)
    }

    @Test func movingIntoVacatingTailIsAllowed() {
        // A 2x2 loop: the head chases its tail, which moves away on the same tick.
        let body = [p(1, 1), p(2, 1), p(2, 2), p(1, 2)]
        var s = S.State(width: 6, height: 6, wallMode: .walls, body: body, direction: .up, food: p(5, 5), seed: 1)
        s.turn(.right)
        let r = s.tick()
        #expect(r.died == nil)
        #expect(s.head == p(1, 2))
    }

    @Test func movingIntoTailWhileEatingIsFatal() {
        // If the tail would stay (growing), it's a real collision. Food can't be on the tail
        // normally, so simulate by placing food exactly where the tail is.
        let body = [p(1, 1), p(2, 1), p(2, 2), p(1, 2)]
        var s = S.State(width: 6, height: 6, wallMode: .walls, body: body, direction: .up, food: p(1, 2), seed: 1)
        s.turn(.right)
        do { let v = s.tick(); #expect(v.died == .selfCollision) }
    }

    // MARK: Winning

    @Test func fillingTheBoardWins() {
        // 2x2 board, snake of 3, food in the last free cell.
        var s = S.State(width: 2, height: 2, wallMode: .walls, body: [p(0, 0), p(1, 0), p(1, 1)],
                        direction: .up, food: p(0, 1), seed: 1)
        s.turn(.right)
        let r = s.tick()
        #expect(r.ate)
        #expect(r.won)
        #expect(s.status == .won)
        #expect(s.food == nil)
        #expect(s.length == 4)
    }

    @Test func hamiltonianPlayoutWinsFullBoard() {
        // Follow a boustrophedon cycle on a 4x4 wrap-free board; the snake must eventually fill it.
        let n = 4
        var cycle: [GridPoint] = []
        for c in 0..<n { cycle.append(p(0, c)) }
        for r in 1..<n {
            let cols = r % 2 == 1 ? Array((1..<n).reversed()) : Array(1..<n)
            for c in cols { cycle.append(p(r, c)) }
        }
        for r in (1..<n).reversed() { cycle.append(p(r, 0)) }
        #expect(cycle.count == n * n)
        var s = S.State(width: n, height: n, wallMode: .walls, body: [p(0, 0)], direction: .right,
                        food: p(0, 2), seed: 9)
        var index = 0
        for _ in 0..<2000 where !s.isOver {
            let next = cycle[(index + 1) % cycle.count]
            let h = s.head
            let dir: Direction = next.row < h.row ? .up : next.row > h.row ? .down : next.col < h.col ? .left : .right
            s.turn(dir)
            let r = s.tick()
            #expect(r.died == nil)
            index = (index + 1) % cycle.count
        }
        #expect(s.status == .won)
        #expect(s.score == n * n - 1)
    }

    // MARK: Persistence

    @Test func codableRoundTrip() throws {
        var s = S.State.newGame(seed: 21)
        s.turn(.up)
        s.tick()
        s.turn(.left)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(S.State.self, from: data)
        #expect(decoded == s)
        var a = s, b = decoded
        for _ in 0..<5 { a.tick(); b.tick() }
        #expect(a == b)
    }

    @Test func speedsAreOrdered() {
        #expect(S.Speed.relaxed.interval > S.Speed.normal.interval)
        #expect(S.Speed.normal.interval > S.Speed.fast.interval)
    }
}
