import SwiftUI
import GameLogic

/// The classic victory effect: cards leap off the foundations one by one and bounce
/// across the table, leaving a trail behind them. Tap to skip.
struct WinCascade: View {
    let foundations: [[Solitaire.Card]]
    let centers: [CGPoint]
    let cardWidth: CGFloat
    /// When the cascade began. Kept by the model so a re-render never restarts it.
    let start: Date
    let onFinish: () -> Void

    private struct Flight {
        let card: Solitaire.Card
        let foundation: Int
        let launch: Double
        let path: [CGPoint]
    }

    private static let interval = 0.085
    private static let fps = 60.0
    private static let trailFrames = 42
    /// When the result card appears (the cascade keeps playing underneath).
    private static let overlayDelay = 2.6

    var body: some View {
        GeometryReader { geo in
            // Deterministic for a given start, so recomputing on a re-render yields the same paths.
            let flights = Self.makeFlights(foundations: foundations, centers: centers, size: geo.size,
                                           cardHeight: cardWidth * SolitaireMetrics.aspect,
                                           seed: UInt64(start.timeIntervalSinceReferenceDate * 1000))
            TimelineView(.animation) { timeline in
                Canvas { ctx, _ in
                    let t = timeline.date.timeIntervalSince(start)
                    // Cards still waiting on each foundation.
                    for f in 0..<min(4, centers.count) {
                        if let waiting = flights.first(where: { $0.foundation == f && $0.launch > t }),
                           let symbol = ctx.resolveSymbol(id: waiting.card.id) {
                            ctx.draw(symbol, at: centers[f])
                        }
                    }
                    for flight in flights where flight.launch <= t {
                        guard let symbol = ctx.resolveSymbol(id: flight.card.id) else { continue }
                        let step = min(flight.path.count - 1, Int((t - flight.launch) * Self.fps))
                        var k = max(0, step - Self.trailFrames)
                        while k < step {
                            ctx.draw(symbol, at: flight.path[k])
                            k += 3
                        }
                        ctx.draw(symbol, at: flight.path[step])
                    }
                } symbols: {
                    ForEach(foundations.flatMap { $0 }) { card in
                        CardFace(card: card, width: cardWidth)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                            .tag(card.id)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .task {
            let remaining = Self.overlayDelay - Date.now.timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            if !Task.isCancelled { onFinish() }
        }
        .accessibilityHidden(true)
    }

    private static func makeFlights(foundations: [[Solitaire.Card]], centers: [CGPoint], size: CGSize,
                                    cardHeight: CGFloat, seed: UInt64) -> [Flight] {
        var rng = SeededRandom(seed: seed)
        var flights: [Flight] = []
        let floor = size.height - cardHeight / 2
        let dt = 1 / fps
        var launch = 0.0
        for rank in stride(from: 13, through: 1, by: -1) {
            for f in foundations.indices where foundations[f].count >= rank && f < centers.count {
                let card = foundations[f][rank - 1]
                var p = centers[f]
                let direction: Double = f < 2 ? -1 : 1
                var vx = CGFloat(Double.random(in: 120...340, using: &rng) * (Bool.random(using: &rng) ? direction : -direction))
                var vy = CGFloat(-Double.random(in: 0...380, using: &rng))
                let gravity: CGFloat = 1900
                var path: [CGPoint] = [p]
                for _ in 0..<Int(fps * 6) {
                    vy += gravity * dt
                    p.x += vx * dt
                    p.y += vy * dt
                    if p.y > floor {
                        p.y = floor
                        vy = -vy * 0.72
                        vx *= 0.98
                    }
                    path.append(p)
                    if p.x < -cardHeight || p.x > size.width + cardHeight { break }
                }
                flights.append(Flight(card: card, foundation: f, launch: launch, path: path))
                launch += interval
            }
        }
        return flights
    }
}
