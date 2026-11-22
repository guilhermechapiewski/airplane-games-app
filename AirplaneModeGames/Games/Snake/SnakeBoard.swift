import SwiftUI
import GameLogic

/// Canvas-rendered board: checkered field, pulsing food and a smooth, interpolated snake.
struct SnakeBoardView: View {
    let model: SnakeModel
    let reduceMotion: Bool

    var body: some View {
        // Stop redrawing once the game-over card is up and nothing is moving.
        TimelineView(.animation(paused: model.showGameOver)) { timeline in
            let frame = Frame(model: model, date: timeline.date)
            Canvas { context, size in
                frame.draw(in: &context, size: size, reduceMotion: reduceMotion)
            }
        }
    }
}

/// An immutable snapshot of everything needed to draw one frame.
private struct Frame {
    let width: Int
    let height: Int
    let wrap: Bool
    let body: [GridPoint]
    let previous: [GridPoint]
    let direction: Direction
    let food: GridPoint?
    let progress: Double
    let time: TimeInterval
    let foodAge: TimeInterval
    let deathAge: TimeInterval?
    let won: Bool
    let eats: [(point: GridPoint, age: TimeInterval)]

    @MainActor init(model: SnakeModel, date: Date) {
        let s = model.state
        width = s.width
        height = s.height
        wrap = s.wallMode == .wrap
        body = s.body
        previous = model.previousBody
        direction = s.direction
        food = s.food
        progress = model.progress(at: date)
        time = date.timeIntervalSinceReferenceDate
        foodAge = date.timeIntervalSince(model.foodBorn)
        deathAge = model.deathDate.map { date.timeIntervalSince($0) }
        won = s.status == .won
        eats = model.eatEvents.map { ($0.point, date.timeIntervalSince($0.date)) }.filter { $0.1 < 0.6 }
    }

    // MARK: Palette

    static let headHex: UInt32 = 0x9BE564
    static let tailHex: UInt32 = 0x23A27A
    static let deadHeadHex: UInt32 = 0xA3A9B5
    static let deadTailHex: UInt32 = 0x6B7280
    static let headColor = Color(hex: headHex)
    static let fieldLight = Color(light: Color(hex: 0xEEF7E8), dark: Color(hex: 0x17201B))
    static let fieldDark = Color(light: Color(hex: 0xE3F0DB), dark: Color(hex: 0x1C2721))
    static let border = Color(light: Color(hex: 0xBFD9B0), dark: Color(hex: 0x2F4436))

    // MARK: Drawing

    func draw(in context: inout GraphicsContext, size: CGSize, reduceMotion: Bool) {
        let cell = min(size.width / CGFloat(width), size.height / CGFloat(height))
        let boardRect = CGRect(x: 0, y: 0, width: cell * CGFloat(width), height: cell * CGFloat(height))
        let corner = cell * 0.6
        let boardPath = Path(roundedRect: boardRect, cornerRadius: corner, style: .continuous)

        // Field.
        context.fill(boardPath, with: .color(Self.fieldLight))
        var checker = Path()
        for r in 0..<height {
            for c in 0..<width where (r + c).isMultiple(of: 2) {
                checker.addRect(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell))
            }
        }
        var clipped = context
        clipped.clip(to: boardPath)
        clipped.fill(checker, with: .color(Self.fieldDark))

        // Food & ripples.
        if let food { drawFood(at: food, cell: cell, in: &clipped, reduceMotion: reduceMotion) }
        for eat in eats {
            let t = eat.age / 0.6
            let center = Self.center(eat.point, cell: cell)
            let radius = cell * (0.5 + 1.1 * t)
            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            clipped.stroke(ring, with: .color(Self.headColor.opacity(0.7 * (1 - t))), lineWidth: cell * 0.14 * (1 - t) + 1)
        }

        // Edge: solid walls, or a dashed line when edges wrap around.
        let edge = Path(roundedRect: boardRect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: corner - 1.5, style: .continuous)
        if wrap {
            context.stroke(edge, with: .color(Self.border),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [cell * 0.35, cell * 0.35]))
        } else {
            context.stroke(edge, with: .color(Self.border), lineWidth: 3)
        }

        drawSnake(cell: cell, in: &clipped, reduceMotion: reduceMotion)
    }

    private static func center(_ p: GridPoint, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(p.row) + 0.5) * cell)
    }

    private func drawFood(at p: GridPoint, cell: CGFloat, in context: inout GraphicsContext, reduceMotion: Bool) {
        let appear = min(1, foodAge / 0.25)
        let pop = appear < 1 ? 1 - pow(1 - appear, 3) * 1.0 : 1
        let pulse = reduceMotion ? 1 : 1 + 0.07 * sin(time * 2 * .pi * 1.2)
        let scale = CGFloat(pop * pulse)
        let c = Self.center(p, cell: cell)
        let r = cell * 0.36 * scale

        // Soft glow.
        let glowR = r * 1.9
        context.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFF5A6E).opacity(0.35), .clear]),
                                           center: c, startRadius: 0, endRadius: glowR))
        // Berry.
        let berry = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.92, width: r * 2, height: r * 1.95))
        context.fill(berry, with: .linearGradient(Gradient(colors: [Color(hex: 0xFF7A88), Color(hex: 0xE3263F)]),
                                                  startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        // Shine.
        let shine = Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.5, height: r * 0.36))
        context.fill(shine, with: .color(.white.opacity(0.75)))
        // Leaf.
        var leafContext = context
        leafContext.translateBy(x: c.x + r * 0.25, y: c.y - r * 1.0)
        leafContext.rotate(by: .degrees(-30))
        let leaf = Path(ellipseIn: CGRect(x: -r * 0.32, y: -r * 0.16, width: r * 0.64, height: r * 0.32))
        leafContext.fill(leaf, with: .color(Color(hex: 0x4CC94A)))
    }

    /// The snake's centre line (in points), head first, for the current interpolation progress.
    ///
    /// Between ticks the head slides from the neck toward its new cell and the tail slides toward
    /// the segment ahead of it; every other joint sits exactly on a cell centre, so corners stay crisp.
    /// In wrap mode consecutive points are "unwrapped" so they are always adjacent (the result may
    /// extend past the board; the caller draws shifted copies).
    private func positions(cell: CGFloat) -> [CGPoint] {
        let t = CGFloat(progress)
        let n = body.count
        func lerp(_ from: GridPoint, _ to: GridPoint) -> CGPoint {
            var dx = CGFloat(to.col - from.col)
            var dy = CGFloat(to.row - from.row)
            // A jump across the board is a one-cell step through a wrapped edge.
            if dx > 1 { dx -= CGFloat(width) } else if dx < -1 { dx += CGFloat(width) }
            if dy > 1 { dy -= CGFloat(height) } else if dy < -1 { dy += CGFloat(height) }
            return CGPoint(x: CGFloat(from.col) + dx * t, y: CGFloat(from.row) + dy * t)
        }
        var grid: [CGPoint] = []
        grid.reserveCapacity(n + 1)
        if n == 1 {
            grid.append(lerp(previous.first ?? body[0], body[0]))
        } else {
            grid.append(lerp(body[1], body[0]))
            for p in body[1...] { grid.append(CGPoint(x: CGFloat(p.col), y: CGFloat(p.row))) }
            let tailPrev = previous.count >= n ? previous[n - 1] : body[n - 1]
            grid.append(lerp(tailPrev, body[n - 1]))
        }
        var result: [CGPoint] = []
        result.reserveCapacity(grid.count)
        for var g in grid {
            if wrap, let last = result.last {
                let lx = last.x / cell - 0.5, ly = last.y / cell - 0.5
                g.x += CGFloat(width) * ((lx - g.x) / CGFloat(width)).rounded()
                g.y += CGFloat(height) * ((ly - g.y) / CGFloat(height)).rounded()
            }
            result.append(CGPoint(x: (g.x + 0.5) * cell, y: (g.y + 0.5) * cell))
        }
        return result
    }

    private func drawSnake(cell: CGFloat, in context: inout GraphicsContext, reduceMotion: Bool) {
        let points = positions(cell: cell)
        guard !points.isEmpty else { return }
        let dead = deathAge != nil
        let headHex = dead ? Self.deadHeadHex : Self.headHex
        let tailHex = dead ? Self.deadTailHex : Self.tailHex
        let head = Color(hex: headHex)
        let n = points.count

        // In wrap mode draw shifted copies so a snake crossing an edge appears on both sides.
        var shifts: [CGSize] = [.zero]
        if wrap {
            let w = cell * CGFloat(width), h = cell * CGFloat(height)
            shifts = [-1, 0, 1].flatMap { sx in [-1, 0, 1].map { sy in CGSize(width: CGFloat(sx) * w, height: CGFloat(sy) * h) } }
        }

        // Shake the dead snake briefly.
        var shake = CGFloat(0)
        if let deathAge, deathAge < 0.4, !reduceMotion {
            shake = CGFloat(sin(deathAge * 70) * (0.4 - deathAge)) * cell * 0.35
        }

        for shift in shifts {
            var ctx = context
            ctx.translateBy(x: shift.width + shake, y: shift.height)

            // Soft drop shadow under the body.
            var shadowPath = Path()
            shadowPath.addLines(points)
            var shadowCtx = ctx
            shadowCtx.addFilter(.blur(radius: cell * 0.08))
            shadowCtx.stroke(shadowPath.offsetBy(dx: 0, dy: cell * 0.12), with: .color(.black.opacity(0.13)),
                             style: StrokeStyle(lineWidth: cell * 0.72, lineCap: .round, lineJoin: .round))

            // Body: tail to head so the head sits on top, with a colour gradient along its length.
            let bodyWidth = cell * 0.78
            if n == 1 {
                let r = cell * 0.4
                ctx.fill(Path(ellipseIn: CGRect(x: points[0].x - r, y: points[0].y - r, width: r * 2, height: r * 2)),
                         with: .color(head))
            }
            for i in stride(from: n - 1, to: 0, by: -1) {
                let f = Double(i) / Double(max(n - 1, 1))
                let color = Self.mix(headHex, tailHex, f)
                if i == n - 1 {
                    // The tip of the tail tapers.
                    for part in Self.taper(from: points[i], width: cell * 0.42, to: points[i - 1], width: bodyWidth) {
                        ctx.fill(part, with: .color(color))
                    }
                } else {
                    var seg = Path()
                    seg.move(to: points[i])
                    seg.addLine(to: points[i - 1])
                    ctx.stroke(seg, with: .color(color),
                               style: StrokeStyle(lineWidth: bodyWidth, lineCap: .round, lineJoin: .round))
                }
            }
            // Glossy stripe along the back.
            var gloss = Path()
            gloss.addLines(points)
            ctx.stroke(gloss.offsetBy(dx: -cell * 0.06, dy: -cell * 0.12), with: .color(.white.opacity(dead ? 0.12 : 0.28)),
                       style: StrokeStyle(lineWidth: cell * 0.16, lineCap: .round, lineJoin: .round))

            drawHead(at: points[0], cell: cell, color: head, dead: dead, in: &ctx)
        }
    }

    private func drawHead(at c: CGPoint, cell: CGFloat, color: Color, dead: Bool, in ctx: inout GraphicsContext) {
        let r = cell * 0.44
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.85, width: r * 0.9, height: r * 0.5)),
                 with: .color(.white.opacity(0.25)))

        let d = CGPoint(x: CGFloat(direction.offset.col), y: CGFloat(direction.offset.row))
        let perp = CGPoint(x: -d.y, y: d.x)
        for side in [-1.0, 1.0] {
            let e = CGPoint(x: c.x + d.x * cell * 0.12 + perp.x * cell * 0.2 * side,
                            y: c.y + d.y * cell * 0.12 + perp.y * cell * 0.2 * side)
            if dead {
                let k = cell * 0.09
                var x = Path()
                x.move(to: CGPoint(x: e.x - k, y: e.y - k)); x.addLine(to: CGPoint(x: e.x + k, y: e.y + k))
                x.move(to: CGPoint(x: e.x + k, y: e.y - k)); x.addLine(to: CGPoint(x: e.x - k, y: e.y + k))
                ctx.stroke(x, with: .color(Color(hex: 0x2A2F3A)), style: StrokeStyle(lineWidth: cell * 0.06, lineCap: .round))
            } else {
                let er = cell * 0.14
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - er, y: e.y - er, width: er * 2, height: er * 2)), with: .color(.white))
                let pr = cell * 0.075
                let pc = CGPoint(x: e.x + d.x * cell * 0.05, y: e.y + d.y * cell * 0.05)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                         with: .color(Color(hex: 0x1D2330)))
                let gr = pr * 0.4
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 0.45 - gr, y: pc.y - pr * 0.45 - gr, width: gr * 2, height: gr * 2)),
                         with: .color(.white))
            }
        }
    }

    /// A rounded wedge between two circles of different widths (filled as separate shapes so
    /// opposite windings don't cancel out).
    private static func taper(from a: CGPoint, width wa: CGFloat, to b: CGPoint, width wb: CGFloat) -> [Path] {
        let ra = wa / 2, rb = wb / 2
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / len, ny = dx / len
        var wedge = Path()
        wedge.move(to: CGPoint(x: a.x + nx * ra, y: a.y + ny * ra))
        wedge.addLine(to: CGPoint(x: b.x + nx * rb, y: b.y + ny * rb))
        wedge.addLine(to: CGPoint(x: b.x - nx * rb, y: b.y - ny * rb))
        wedge.addLine(to: CGPoint(x: a.x - nx * ra, y: a.y - ny * ra))
        wedge.closeSubpath()
        return [Path(ellipseIn: CGRect(x: a.x - ra, y: a.y - ra, width: wa, height: wa)),
                Path(ellipseIn: CGRect(x: b.x - rb, y: b.y - rb, width: wb, height: wb)),
                wedge]
    }

    /// Linear blend between two 0xRRGGBB colours.
    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
        func lerp(_ shift: UInt32) -> Double { channel(a, shift) + (channel(b, shift) - channel(a, shift)) * t }
        return Color(.sRGB, red: lerp(16), green: lerp(8), blue: lerp(0))
    }
}
