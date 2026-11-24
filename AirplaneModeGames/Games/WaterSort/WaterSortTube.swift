import SwiftUI
import GameLogic

/// The twelve liquids. Neighbouring hues get very different symbols, which appear on every layer
/// when Differentiate Without Color is on.
struct LiquidStyle {
    let name: String
    let color: Color
    let highlight: Color
    let symbol: String
    /// The symbol drawn dark (on light liquids) rather than light.
    let darkMark: Bool

    static let all: [LiquidStyle] = [
        LiquidStyle(name: "red", color: Color(hex: 0xE5383B), highlight: Color(hex: 0xFF7A72), symbol: "heart.fill", darkMark: false),
        LiquidStyle(name: "orange", color: Color(hex: 0xF58A1F), highlight: Color(hex: 0xFFB561), symbol: "triangle.fill", darkMark: true),
        LiquidStyle(name: "yellow", color: Color(hex: 0xF7CB2D), highlight: Color(hex: 0xFFE57A), symbol: "star.fill", darkMark: true),
        LiquidStyle(name: "lime", color: Color(hex: 0x9ACD32), highlight: Color(hex: 0xC6EE6E), symbol: "leaf.fill", darkMark: true),
        LiquidStyle(name: "green", color: Color(hex: 0x1F8A4C), highlight: Color(hex: 0x45B572), symbol: "suit.club.fill", darkMark: false),
        LiquidStyle(name: "teal", color: Color(hex: 0x22B8B0), highlight: Color(hex: 0x66DCD3), symbol: "square.fill", darkMark: true),
        LiquidStyle(name: "sky blue", color: Color(hex: 0x5BB8F5), highlight: Color(hex: 0x9AD6FF), symbol: "cloud.fill", darkMark: true),
        LiquidStyle(name: "blue", color: Color(hex: 0x2F4FD8), highlight: Color(hex: 0x6582F2), symbol: "moon.fill", darkMark: false),
        LiquidStyle(name: "purple", color: Color(hex: 0x8A4FD6), highlight: Color(hex: 0xB487F0), symbol: "diamond.fill", darkMark: false),
        LiquidStyle(name: "pink", color: Color(hex: 0xF36FB5), highlight: Color(hex: 0xFFA3D4), symbol: "circle.fill", darkMark: true),
        LiquidStyle(name: "brown", color: Color(hex: 0x8A5532), highlight: Color(hex: 0xB47D55), symbol: "bolt.fill", darkMark: false),
        LiquidStyle(name: "silver", color: Color(hex: 0xA9B3BF), highlight: Color(hex: 0xD6DDE5), symbol: "plus", darkMark: true),
    ]

    static func of(_ liquid: Int) -> LiquidStyle { all[liquid % all.count] }
}

/// Proportions of a tube, in points, from its width.
struct TubeMetrics {
    let width: CGFloat
    var layer: CGFloat { width * 0.86 }
    /// Room above the liquid of a full tube.
    var headroom: CGFloat { width * 0.62 }
    var lip: CGFloat { width * 0.12 }
    var height: CGFloat { layer * CGFloat(WaterSort.capacity) + headroom + lip }
    var wall: CGFloat { max(1.5, width * 0.055) }
    /// The liquid's bottom (inside the rounded end).
    var bottomY: CGFloat { height - wall }
    var interiorWidth: CGFloat { width - 2 * wall }

    static let heightRatio: CGFloat = 0.86 * CGFloat(WaterSort.capacity) + 0.62 + 0.12
}

/// Glass outline: a lip at the top and a fully rounded bottom.
struct TubeShape: Shape {
    var inset: CGFloat = 0
    var lip: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = r.width / 2
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + lip))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + lip))
        return p
    }
}

/// One tube and its liquid. `amounts` are layer heights in units (fractional mid-pour), bottom first.
/// `tilt` is the tube's rotation, so the liquid's surface can stay level with the ground.
struct TubeView: View {
    let metrics: TubeMetrics
    let layers: [(liquid: Int, amount: Double)]
    var tilt: Angle = .zero
    var isSelected = false
    var isComplete = false
    var symbols = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let m = metrics
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            // Glass body.
            TubeShape(lip: m.lip)
                .fill(dark ? Color.white.opacity(0.07) : Color.white.opacity(0.75))
            Canvas { ctx, size in
                drawLiquid(in: &ctx, size: size)
            }
            if symbols { marks }
            // Glass rim and shine.
            TubeShape(lip: m.lip)
                .stroke(rimColor(dark: dark), style: StrokeStyle(lineWidth: m.wall, lineCap: .round, lineJoin: .round))
            Capsule()
                .fill(Color.white.opacity(dark ? 0.14 : 0.4))
                .frame(width: m.width * 0.08, height: m.height * 0.66)
                .offset(x: -m.width * 0.25, y: m.lip + m.headroom * 0.55)
            // Lip.
            Capsule()
                .fill(rimColor(dark: dark))
                .frame(width: m.width + m.wall * 2.2, height: m.lip * 1.1)
                .offset(y: -m.lip * 0.15)
            if isComplete, let top = layers.last?.liquid { cap(top) }
        }
        .frame(width: m.width, height: m.height)
    }

    private func rimColor(dark: Bool) -> Color {
        if isSelected { return GameID.waterSort.accent }
        return dark ? Color.white.opacity(0.42) : Color(hex: 0x8E9AB0).opacity(0.75)
    }

    /// A stopper on a finished tube.
    private func cap(_ liquid: Int) -> some View {
        let m = metrics
        let style = LiquidStyle.of(liquid)
        return RoundedRectangle(cornerRadius: m.width * 0.14, style: .continuous)
            .fill(LinearGradient(colors: [style.highlight, style.color], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: m.width * 0.14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
            }
            .frame(width: m.width * 0.78, height: m.headroom * 0.62)
            .offset(y: m.lip * 0.4)
            .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
    }

    /// The liquid, clipped to the glass, with a level surface whatever the tilt.
    private func drawLiquid(in ctx: inout GraphicsContext, size: CGSize) {
        let m = metrics
        ctx.clip(to: TubeShape(inset: m.wall * 0.5, lip: m.lip).path(in: CGRect(origin: .zero, size: size)))
        // tan of the surface slope in the tube's own frame; capped so lines stay finite.
        let slope = CGFloat(tan(max(-1.45, min(1.45, tilt.radians))))
        let mid = size.width / 2
        // Lines below the bottom start at the bottom of the rounded end; extend well past the sides.
        func line(_ level: Double) -> (CGPoint, CGPoint) {
            let y = m.bottomY - CGFloat(level) * m.layer
            let ext = size.width * 3
            return (CGPoint(x: mid - ext, y: y + ext * slope), CGPoint(x: mid + ext, y: y - ext * slope))
        }
        // Neighbouring layers of one color are drawn as one band, without seams.
        var runs: [(liquid: Int, amount: Double)] = []
        for layer in layers where layer.amount > 0.001 {
            if let last = runs.last, last.liquid == layer.liquid {
                runs[runs.count - 1].amount += layer.amount
            } else {
                runs.append(layer)
            }
        }
        var level = 0.0
        for (i, run) in runs.enumerated() {
            let style = LiquidStyle.of(run.liquid)
            let lower = level == 0 ? -4 : level
            let upper = level + run.amount
            let (a, b) = line(lower), (c, d) = line(upper)
            var band = Path()
            band.addLines([a, b, d, c])
            band.closeSubpath()
            ctx.fill(band, with: .linearGradient(Gradient(colors: [style.highlight, style.color, style.color.opacity(0.92)]),
                                                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
            if i == runs.count - 1 {
                // A light meniscus on the surface.
                var surface = Path()
                surface.move(to: c)
                surface.addLine(to: d)
                ctx.stroke(surface, with: .color(Color.white.opacity(0.45)), lineWidth: max(1, m.width * 0.05))
            }
            level = upper
        }
    }

    /// Differentiate Without Color: each layer carries its liquid's symbol.
    private var marks: some View {
        let m = metrics
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(layers.enumerated().reversed()), id: \.offset) { _, layer in
                let style = LiquidStyle.of(layer.liquid)
                Image(systemName: style.symbol)
                    .font(.system(size: m.width * 0.36, weight: .heavy))
                    .foregroundStyle(style.darkMark ? Color.black.opacity(0.55) : Color.white.opacity(0.92))
                    .frame(width: m.width, height: m.layer * CGFloat(max(0, layer.amount)))
                    .opacity(layer.amount > 0.6 ? 1 : 0)
            }
        }
        .padding(.bottom, m.wall)
        .frame(width: m.width, height: m.height)
        .allowsHitTesting(false)
    }
}
