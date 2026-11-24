import SwiftUI
import GameLogic

/// Ink-on-paper colours, with a blue / orange player pair that stays distinct for most kinds
/// of colour blindness.
enum DotsTheme {
    static let accent = GameID.dotsAndBoxes.accent
    static let one = Color(light: Color(hex: 0x2F6BEA), dark: Color(hex: 0x5E9BFF))
    static let two = Color(light: Color(hex: 0xEA7317), dark: Color(hex: 0xFF9A45))
    static let dot = Color(light: Color(hex: 0x2B2540), dark: Color(hex: 0xEDE8F7))
    static let slot = Color(light: Color(hex: 0xDDD7EB), dark: Color(hex: 0x363149))
    static let paper = Color(light: Color(hex: 0xFFFEFB), dark: Color(hex: 0x1C1A26))
    static let paperEdge = Color(light: Color(hex: 0xE7E2F0), dark: Color(hex: 0x2E2A3C))
    /// Hinted line: green, distinct from both players' colours.
    static let hint = Color(light: Color(hex: 0x2E9B57), dark: Color(hex: 0x4CC27A))

    static func color(_ player: DotsAndBoxes.Player) -> Color { player == .one ? one : two }
}

/// Dot spacing and positions for a board drawn in a square of `side` points.
struct DotsGeometry {
    let size: Int
    let side: CGFloat

    var spacing: CGFloat { side / (CGFloat(size) + 0.9) }
    var margin: CGFloat { spacing * 0.45 }
    var lineWidth: CGFloat { min(12, max(5, spacing * 0.1)) }
    var dotSize: CGFloat { min(16, max(8, spacing * 0.17)) }

    func point(row: Int, col: Int) -> CGPoint {
        CGPoint(x: margin + CGFloat(col) * spacing, y: margin + CGFloat(row) * spacing)
    }

    func endpoints(_ line: DotsAndBoxes.Line) -> (CGPoint, CGPoint) {
        let (a, b) = line.dots
        return (point(row: a.row, col: a.col), point(row: b.row, col: b.col))
    }

    func midpoint(_ line: DotsAndBoxes.Line) -> CGPoint {
        let (a, b) = endpoints(line)
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    func center(ofBox box: GridPoint) -> CGPoint {
        CGPoint(x: margin + (CGFloat(box.col) + 0.5) * spacing, y: margin + (CGFloat(box.row) + 0.5) * spacing)
    }

    /// The undrawn line nearest to a touch, if it's close enough to be meant.
    func nearestLine(to p: CGPoint, among lines: [DotsAndBoxes.Line]) -> DotsAndBoxes.Line? {
        var best: DotsAndBoxes.Line?
        var bestDistance = spacing * 0.46
        for line in lines {
            let (a, b) = endpoints(line)
            let d = Self.distance(from: p, toSegment: a, b)
            if d < bestDistance {
                bestDistance = d
                best = line
            }
        }
        return best
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

struct DotsBoardView: View {
    let model: DotsAndBoxesModel
    let side: CGFloat

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor
    @State private var pressed: DotsAndBoxes.Line?
    @GestureState private var touchActive = false

    private var game: DotsAndBoxes.Game { model.game }
    private var geo: DotsGeometry { DotsGeometry(size: game.rows, side: side) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            slots
            boxes
            drawnLines
            pressedPreview
            hintMarker
            dots
            lastMoveMarker
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(touch)
        .onGestureCancelled(touchActive) { pressed = nil }
        .onChange(of: model.isHumanTurn) { _, canPlay in if !canPlay { pressed = nil } }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22), value: model.changeCount)
        .overlay(alignment: .topLeading) { accessibilityLayer }
        .background {
            RoundedRectangle(cornerRadius: max(14, side * 0.045), style: .continuous)
                .fill(DotsTheme.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: max(14, side * 0.045), style: .continuous)
                        .strokeBorder(DotsTheme.paperEdge, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board, \(game.rows) by \(game.cols) boxes")
        .accessibilityIdentifier("dotsBoard")
    }

    // MARK: Layers

    /// Faint guides where lines can still go.
    private var slots: some View {
        let geo = geo
        let game = game
        return Canvas { context, _ in
            let inset = geo.dotSize * 0.9
            for i in 0..<game.edgeCount where !game.drawn[i] {
                let (a, b) = geo.endpoints(game.line(at: i))
                var path = Path()
                if a.y == b.y {
                    path.move(to: CGPoint(x: a.x + inset, y: a.y))
                    path.addLine(to: CGPoint(x: b.x - inset, y: b.y))
                } else {
                    path.move(to: CGPoint(x: a.x, y: a.y + inset))
                    path.addLine(to: CGPoint(x: b.x, y: b.y - inset))
                }
                context.stroke(path, with: .color(DotsTheme.slot),
                               style: StrokeStyle(lineWidth: max(2, geo.lineWidth * 0.42), lineCap: .round))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var dots: some View {
        let geo = geo
        let n = game.rows
        return Canvas { context, _ in
            let r = geo.dotSize / 2
            for row in 0...n {
                for col in 0...n {
                    let p = geo.point(row: row, col: col)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(DotsTheme.dot))
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var drawnLines: some View {
        let geo = geo
        return ForEach(drawnIndices, id: \.self) { i in
            let line = game.line(at: i)
            let owner = game.lineOwners[i]
            DotsLineShape(geometry: geo, line: line)
                .fill(owner.map(DotsTheme.color) ?? DotsTheme.dot.opacity(0.75))
                .transition(reduceMotion ? .opacity : .lineGrow(line, in: geo))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var drawnIndices: [Int] { game.drawn.indices.filter { game.drawn[$0] } }

    @ViewBuilder private var pressedPreview: some View {
        if let pressed, model.canDraw(pressed) {
            DotsLineShape(geometry: geo, line: pressed, widthScale: 1.25)
                .fill(DotsTheme.color(game.current).opacity(0.45))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The suggested line: a pulsing dashed bar with ringed end dots (a shape, not just a colour).
    @ViewBuilder private var hintMarker: some View {
        if let line = model.hint?.line, !game.isDrawn(line) {
            let geo = geo
            let (a, b) = geo.endpoints(line)
            let w = geo.lineWidth
            ZStack(alignment: .topLeading) {
                DotsLineShape(geometry: geo, line: line, widthScale: 2.1)
                    .fill(DotsTheme.hint.opacity(0.22))
                Path { p in
                    p.move(to: a)
                    p.addLine(to: b)
                }
                .stroke(DotsTheme.hint, style: StrokeStyle(lineWidth: w, lineCap: .round, dash: [w * 1.2, w * 1.1]))
                Circle()
                    .strokeBorder(DotsTheme.hint, lineWidth: max(2, geo.dotSize * 0.22))
                    .frame(width: geo.dotSize * 2.2, height: geo.dotSize * 2.2)
                    .position(a)
                Circle()
                    .strokeBorder(DotsTheme.hint, lineWidth: max(2, geo.dotSize * 0.22))
                    .frame(width: geo.dotSize * 2.2, height: geo.dotSize * 2.2)
                    .position(b)
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, phase in
                content.opacity(phase)
            } animation: { _ in .easeInOut(duration: 0.7) }
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var boxes: some View {
        let geo = geo
        let claimed = (0..<game.boxCount).compactMap { i -> (GridPoint, DotsAndBoxes.Player)? in
            let box = GridPoint(row: i / game.cols, col: i % game.cols)
            return game.owner(ofBox: box).map { (box, $0) }
        }
        return ForEach(claimed, id: \.0) { box, owner in
            DotsBoxFill(owner: owner, initial: model.initial(for: owner), size: geo.spacing - geo.lineWidth,
                        marked: differentiateWithoutColor)
                .position(geo.center(ofBox: box))
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
                    .animation(.spring(response: 0.32, dampingFraction: 0.55)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The latest line gets a light centre stripe and ringed end dots, so it reads without colour.
    @ViewBuilder private var lastMoveMarker: some View {
        if let line = model.lastLine {
            let geo = geo
            let (a, b) = geo.endpoints(line)
            ZStack(alignment: .topLeading) {
                DotsLineShape(geometry: geo, line: line, widthScale: 0.32, inset: geo.dotSize * 0.75)
                    .fill(.white.opacity(0.9))
                ringedDot(at: a)
                ringedDot(at: b)
            }
            .id(model.changeCount)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func ringedDot(at p: CGPoint) -> some View {
        Circle()
            .strokeBorder(DotsTheme.dot, lineWidth: max(1.5, geo.dotSize * 0.18))
            .frame(width: geo.dotSize * 1.9, height: geo.dotSize * 1.9)
            .position(p)
    }

    // MARK: Input

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .tracking($touchActive)
            .onChanged { value in
                guard model.isHumanTurn else { return }
                let line = geo.nearestLine(to: value.location, among: game.availableLines)
                if line != pressed {
                    pressed = line
                    if line != nil { Haptics.select() }
                }
            }
            .onEnded { value in
                let line = geo.nearestLine(to: value.location, among: game.availableLines) ?? pressed
                pressed = nil
                if let line { model.tap(line) }
            }
    }

    // MARK: Accessibility

    /// One element per open line (activate to draw it) and per claimed box, in reading order.
    private var accessibilityLayer: some View {
        let geo = geo
        let open = game.availableLines
        let boxes = (0..<game.boxCount).compactMap { i -> (GridPoint, DotsAndBoxes.Player)? in
            let box = GridPoint(row: i / game.cols, col: i % game.cols)
            return game.owner(ofBox: box).map { (box, $0) }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(open, id: \.self) { line in
                let mid = geo.midpoint(line)
                let long = geo.spacing * 0.62, short = geo.spacing * 0.42
                let isH = line.orientation == .horizontal
                Color.clear
                    .frame(width: isH ? long : short, height: isH ? short : long)
                    .position(mid)
                    .accessibilityElement()
                    .accessibilityLabel(DotsAndBoxesModel.spokenName(of: line).capitalizedFirst)
                    .accessibilityValue(lineValue(line))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("line.\(isH ? "h" : "v").\(line.row).\(line.col)")
                    .accessibilityAction { model.tap(line) }
            }
            ForEach(boxes, id: \.0) { box, owner in
                Color.clear
                    .frame(width: geo.spacing * 0.5, height: geo.spacing * 0.5)
                    .position(geo.center(ofBox: box))
                    .accessibilityElement()
                    .accessibilityLabel("Box row \(box.row + 1) column \(box.col + 1)")
                    .accessibilityValue(model.setup.isComputer
                                        ? (owner == DotsAndBoxesModel.human ? "Yours" : "Computer's")
                                        : "\(model.name(for: owner))'s")
                    .accessibilityIdentifier("box.\(box.row).\(box.col)")
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func lineValue(_ line: DotsAndBoxes.Line) -> String {
        let base = baseLineValue(line)
        guard model.hint?.line == line else { return base }
        return base.isEmpty ? "Hint" : "Hint, " + base.lowercased()
    }

    private func baseLineValue(_ line: DotsAndBoxes.Line) -> String {
        let sides = game.boxes(adjacentTo: line).map { game.sides(of: $0) }
        if sides.contains(3) { return sides.filter { $0 == 3 }.count == 2 ? "Completes two boxes" : "Completes a box" }
        if sides.contains(2) { return "Gives away a box" }
        return ""
    }
}

/// A rounded bar between two dots.
struct DotsLineShape: Shape {
    let geometry: DotsGeometry
    let line: DotsAndBoxes.Line
    var widthScale: CGFloat = 1
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let (a, b) = geometry.endpoints(line)
        let w = geometry.lineWidth * widthScale
        let r: CGRect
        if line.orientation == .horizontal {
            r = CGRect(x: a.x + inset, y: a.y - w / 2, width: b.x - a.x - inset * 2, height: w)
        } else {
            r = CGRect(x: a.x - w / 2, y: a.y + inset, width: w, height: b.y - a.y - inset * 2)
        }
        return Path(roundedRect: r, cornerRadius: w / 2)
    }
}

/// A claimed box: a soft tile in the owner's colour with their letter. With Differentiate
/// Without Colour, player two's tiles are also hatched and player one's carry a ring.
struct DotsBoxFill: View {
    let owner: DotsAndBoxes.Player
    let initial: String
    let size: CGFloat
    var marked = false

    var body: some View {
        let color = DotsTheme.color(owner)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(color.opacity(0.2))
            if marked {
                if owner == .two {
                    DotsHatch(spacing: max(5, size * 0.16))
                        .stroke(color.opacity(0.45), lineWidth: max(1, size * 0.03))
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
                } else {
                    Circle()
                        .strokeBorder(color.opacity(0.7), lineWidth: max(1.5, size * 0.05))
                        .frame(width: size * 0.66, height: size * 0.66)
                }
            }
            Text(initial)
                .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// Diagonal hatching.
struct DotsHatch: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// Grows a line outward from its midpoint when it's drawn.
private struct LineGrowModifier: ViewModifier {
    let progress: CGFloat
    let horizontal: Bool
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: horizontal ? progress : 1, y: horizontal ? 1 : progress, anchor: anchor)
            .opacity(progress < 0.05 ? 0 : 1)
    }
}

private extension AnyTransition {
    static func lineGrow(_ line: DotsAndBoxes.Line, in geo: DotsGeometry) -> AnyTransition {
        let mid = geo.midpoint(line)
        let anchor = UnitPoint(x: mid.x / geo.side, y: mid.y / geo.side)
        let horizontal = line.orientation == .horizontal
        return .modifier(active: LineGrowModifier(progress: 0.01, horizontal: horizontal, anchor: anchor),
                         identity: LineGrowModifier(progress: 1, horizontal: horizontal, anchor: anchor))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
