import SwiftUI
import GameLogic

/// Original artwork for every tile face, drawn with SF Symbols and type.
struct TileFaceArt: View {
    let face: TileMatch.Face
    /// Width of the tile face.
    let width: CGFloat

    var body: some View {
        let style = FaceStyle.of(face)
        Group {
            if face.suit.isNumbered {
                VStack(spacing: -width * 0.02) {
                    Image(systemName: style.symbol)
                        .font(.system(size: width * 0.28, weight: .bold))
                    Text("\(face.rank)")
                        .font(.system(size: width * 0.6, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(style.gradient)
            } else if face.suit.isBonus {
                ZStack {
                    RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                        .strokeBorder(style.frame, style: StrokeStyle(lineWidth: max(1, width * 0.045), dash: [width * 0.08, width * 0.05]))
                        .padding(width * 0.07)
                    Image(systemName: style.symbol)
                        .font(.system(size: width * 0.5, weight: .semibold))
                        .foregroundStyle(style.gradient)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(style.color.opacity(0.13))
                        .frame(width: width * 0.8, height: width * 0.8)
                    Image(systemName: style.symbol)
                        .font(.system(size: width * 0.5, weight: .bold))
                        .foregroundStyle(style.gradient)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

struct FaceStyle {
    let symbol: String
    let color: Color
    let name: String
    let gradient: LinearGradient

    private init(_ face: TileMatch.Face) {
        let r = face.rank
        switch face.suit {
        case .ocean: (symbol, color, name) = ("drop.fill", Color(hex: 0x1F6FD6), "Ocean \(r)")
        case .forest: (symbol, color, name) = ("leaf.fill", Color(hex: 0x15924C), "Forest \(r)")
        case .ember: (symbol, color, name) = ("flame.fill", Color(hex: 0xD93A2B), "Ember \(r)")
        case .weather:
            (symbol, color, name) = [
                ("sun.max.fill", Color(hex: 0xEE8A00), "Sun"),
                ("cloud.fill", Color(hex: 0x56739A), "Cloud"),
                ("snowflake", Color(hex: 0x119EC4), "Snowflake"),
                ("bolt.fill", Color(hex: 0x8A46DD), "Lightning"),
            ][r - 1]
        case .charm:
            (symbol, color, name) = [
                ("heart.fill", Color(hex: 0xE02D69), "Heart"),
                ("star.fill", Color(hex: 0xDB9E00), "Star"),
                ("moon.fill", Color(hex: 0x4848C2), "Moon"),
            ][r - 1]
        case .treasure:
            (symbol, color, name) = [
                ("crown.fill", Color(hex: 0xC98600), "Crown treasure"),
                ("gift.fill", Color(hex: 0xD6406A), "Gift treasure"),
                ("key.fill", Color(hex: 0x9A6A1E), "Key treasure"),
                ("bell.fill", Color(hex: 0xE07000), "Bell treasure"),
            ][r - 1]
        case .critter:
            (symbol, color, name) = [
                ("bird.fill", Color(hex: 0x2A86D1), "Bird critter"),
                ("fish.fill", Color(hex: 0x0E9A96), "Fish critter"),
                ("tortoise.fill", Color(hex: 0x3A9436), "Tortoise critter"),
                ("hare.fill", Color(hex: 0x9C6640), "Hare critter"),
            ][r - 1]
        }
        gradient = LinearGradient(colors: [color.blended(with: .white, 0.12), color.blended(with: .black, 0.14)],
                                  startPoint: .top, endPoint: .bottom)
    }


    @MainActor private static let cache: [TileMatch.Face: FaceStyle] = Dictionary(
        uniqueKeysWithValues: TileMatch.Face.all.map { ($0, FaceStyle($0)) })

    @MainActor static func of(_ face: TileMatch.Face) -> FaceStyle { cache[face] ?? FaceStyle(face) }

    var frame: Color {
        color.opacity(0.55)
    }
}

private extension Color {
    /// Simple sRGB blend (`Color.mix` needs iOS 18).
    func blended(with other: Color, _ amount: CGFloat) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                     blue: b1 + (b2 - b1) * amount, opacity: a1 + (a2 - a1) * amount)
    }
}
