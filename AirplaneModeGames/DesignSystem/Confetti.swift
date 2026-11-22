import SwiftUI

/// Lightweight celebratory confetti rendered with Canvas. Honors Reduce Motion.
struct ConfettiView: View {
    var colors: [Color] = [.yellow, .pink, .mint, .orange, .purple, .blue]
    var count = 90

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pieces: [Piece] = []

    private struct Piece {
        let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Int
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSince(start)
                    for p in pieces {
                        let local = t - p.delay
                        guard local > 0 else { continue }
                        let y = -20 + local * p.speed * size.height * 0.45
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(local * 2 + p.drift) * 24
                        let fade = max(0, min(1, 3.2 - local))
                        var c = ctx
                        c.opacity = fade
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(local * p.spin))
                        let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                        c.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[p.color % colors.count]))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                start = .now
                pieces = (0..<count).map { _ in
                    Piece(x: .random(in: 0...1), delay: .random(in: 0...0.6), speed: .random(in: 0.7...1.3),
                          drift: .random(in: 0...6), spin: .random(in: -6...6), size: .random(in: 7...13),
                          color: .random(in: 0..<colors.count))
                }
            }
        }
    }
}
