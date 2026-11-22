import SwiftUI
import GameLogic

/// Colors of the solitaire table and cards.
enum SolitairePalette {
    static let feltCenter = Color(light: Color(hex: 0x3A9C66), dark: Color(hex: 0x1C5A3B))
    static let feltEdge = Color(light: Color(hex: 0x1F6D45), dark: Color(hex: 0x0A2618))
    static let cardTop = Color(light: .white, dark: Color(hex: 0xEDEAE2))
    static let cardBottom = Color(light: Color(hex: 0xF6F3EC), dark: Color(hex: 0xDEDAD0))
    static let red = Color(hex: 0xD12A3C)
    static let black = Color(hex: 0x1E2532)
    static let backTop = Color(hex: 0x23A866)
    static let backBottom = Color(hex: 0x0F5A37)
    static let slot = Color.white.opacity(0.16)
    static let hint = Color(hex: 0xFFD54A)

    static func ink(_ suit: Solitaire.Suit) -> Color { suit.isRed ? red : black }
}

/// The SF Symbol for a suit pip.
extension Solitaire.Suit {
    var symbolName: String {
        switch self {
        case .spades: "suit.spade.fill"
        case .hearts: "suit.heart.fill"
        case .diamonds: "suit.diamond.fill"
        case .clubs: "suit.club.fill"
        }
    }
}

/// A playing card that turns over in 3D when `faceUp` changes inside an animation.
struct PlayingCard: View, Animatable {
    let card: Solitaire.Card
    let width: CGFloat
    /// 0 = face up, 180 = face down.
    var angle: Double

    init(card: Solitaire.Card, faceUp: Bool, width: CGFloat) {
        self.card = card
        self.width = width
        self.angle = faceUp ? 0 : 180
    }

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        Group {
            if angle < 90 {
                CardFace(card: card, width: width)
            } else {
                CardBack(width: width)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}

/// The front of a card: rank and suit in the corners and a large center pip or monogram.
struct CardFace: View {
    let card: Solitaire.Card
    let width: CGFloat

    var body: some View {
        let height = width * SolitaireMetrics.aspect
        let radius = width * SolitaireMetrics.cornerRatio
        let ink = SolitairePalette.ink(card.suit)
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [SolitairePalette.cardTop, SolitairePalette.cardBottom],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.black.opacity(0.16), lineWidth: max(0.5, width * 0.008))

            // Top corner: always visible in a fanned column.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(card.rankSymbol)
                    .font(.system(size: width * (card.rank == 10 ? 0.28 : 0.31), weight: .bold, design: .serif))
                    .tracking(card.rank == 10 ? -width * 0.025 : 0)
                Spacer(minLength: 0)
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: width * 0.22, weight: .bold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, width * 0.075)
            .padding(.top, width * 0.04)
            .frame(maxHeight: .infinity, alignment: .top)

            center(ink: ink)
                .offset(y: height * 0.09)

            // Bottom corner, upside down like a real card.
            VStack(spacing: -width * 0.02) {
                Text(card.rankSymbol)
                    .font(.system(size: width * 0.17, weight: .bold, design: .serif))
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: width * 0.12, weight: .bold))
            }
            .foregroundStyle(ink.opacity(0.85))
            .rotationEffect(.degrees(180))
            .padding(width * 0.06)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: width, height: height)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .dynamicTypeSize(.large)
    }

    @ViewBuilder private func center(ink: Color) -> some View {
        switch card.rank {
        case 1:
            ZStack {
                Circle()
                    .strokeBorder(ink.opacity(0.25), lineWidth: max(0.5, width * 0.012))
                    .frame(width: width * 0.62, height: width * 0.62)
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: width * 0.38, weight: .bold))
                    .foregroundStyle(ink)
            }
        case 11...13:
            FaceMonogram(card: card, width: width, ink: ink)
        default:
            Image(systemName: card.suit.symbolName)
                .font(.system(size: width * 0.42, weight: .bold))
                .foregroundStyle(ink)
        }
    }
}

/// A framed monogram for Jacks, Queens and Kings.
private struct FaceMonogram: View {
    let card: Solitaire.Card
    let width: CGFloat
    let ink: Color

    private var emblem: String {
        switch card.rank {
        case 13: "crown.fill"
        case 12: "sparkle"
        default: "shield.lefthalf.filled"
        }
    }

    var body: some View {
        let w = width * 0.66, h = width * 0.78
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .fill(ink.opacity(0.09))
            RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                .strokeBorder(ink.opacity(0.45), lineWidth: max(0.5, width * 0.014))
            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                .strokeBorder(ink.opacity(0.18), lineWidth: max(0.5, width * 0.008))
                .padding(width * 0.035)
            VStack(spacing: width * 0.0) {
                Image(systemName: emblem)
                    .font(.system(size: width * 0.13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC9962B))
                Text(card.rankSymbol)
                    .font(.system(size: width * 0.36, weight: .heavy, design: .serif))
                    .foregroundStyle(ink)
            }
        }
        .frame(width: w, height: h)
    }
}

/// The back of a card: a green lattice with a small airplane emblem.
struct CardBack: View {
    let width: CGFloat

    var body: some View {
        let height = width * SolitaireMetrics.aspect
        let radius = width * SolitaireMetrics.cornerRatio
        let inset = width * 0.07
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [SolitairePalette.backTop, SolitairePalette.backBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let spacing = size.width / 5
                var lattice = Path()
                var x = -size.height
                while x < size.width + size.height {
                    lattice.move(to: CGPoint(x: x, y: 0))
                    lattice.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    lattice.move(to: CGPoint(x: x + size.height, y: 0))
                    lattice.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                ctx.clip(to: Path(roundedRect: rect, cornerRadius: radius * 0.6))
                ctx.stroke(lattice, with: .color(.white.opacity(0.16)), lineWidth: max(0.5, size.width * 0.02))
                // Soft glow behind the emblem.
                let glow = CGRect(x: size.width * 0.15, y: size.height / 2 - size.width * 0.35,
                                  width: size.width * 0.7, height: size.width * 0.7)
                ctx.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [SolitairePalette.backBottom, SolitairePalette.backBottom.opacity(0)]),
                    center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 0, endRadius: glow.width / 2))
            }
            .padding(inset)
            RoundedRectangle(cornerRadius: radius * 0.6, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: max(0.75, width * 0.018))
                .padding(inset)
            Circle()
                .fill(SolitairePalette.backBottom)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: max(0.5, width * 0.014)))
                .frame(width: width * 0.36, height: width * 0.36)
                .overlay {
                    Image(systemName: "airplane")
                        .font(.system(size: width * 0.17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .rotationEffect(.degrees(-45))
                }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.black.opacity(0.25), lineWidth: max(0.5, width * 0.008))
        }
        .frame(width: width, height: height)
        .dynamicTypeSize(.large)
    }
}

/// An empty place on the table (stock, foundation or column).
struct PileSlot: View {
    let width: CGFloat
    var symbol: String?
    var label: String?
    var highlighted = false

    var body: some View {
        let radius = width * SolitaireMetrics.cornerRatio
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.black.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(highlighted ? SolitairePalette.hint : SolitairePalette.slot,
                                  style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.5, dash: highlighted ? [] : [5, 4]))
            }
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: width * 0.34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.32))
                } else if let label {
                    Text(label)
                        .font(.system(size: width * 0.38, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }
            .frame(width: width, height: width * SolitaireMetrics.aspect)
            .dynamicTypeSize(.large)
    }
}

/// Felt-like table surface: a soft radial gradient with a fine fiber texture.
struct FeltBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [SolitairePalette.feltCenter, SolitairePalette.feltEdge],
                               center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.8)
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 0xFE17)
                    let count = Int(size.width * size.height / 90)
                    for i in 0..<count {
                        let x = Double(rng.next() % 10_000) / 10_000 * size.width
                        let y = Double(rng.next() % 10_000) / 10_000 * size.height
                        let r = 0.4 + Double(rng.next() % 100) / 100 * 0.6
                        let color: Color = i.isMultiple(of: 2) ? .white.opacity(0.05) : .black.opacity(0.07)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(color))
                    }
                }
                .drawingGroup()
                // Vignette.
                RadialGradient(colors: [.clear, .black.opacity(0.22)], center: .center,
                               startRadius: min(geo.size.width, geo.size.height) * 0.45,
                               endRadius: max(geo.size.width, geo.size.height) * 0.85)
            }
        }
        .accessibilityHidden(true)
    }
}

enum SolitaireMetrics {
    static let aspect: CGFloat = 1.42
    static let cornerRatio: CGFloat = 0.09
}
