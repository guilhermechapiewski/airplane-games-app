import SwiftUI
import GameLogic

/// Original vector chess pieces, drawn in a 100×100 design space and scaled to fit.
/// Each piece is a back-to-front list of parts: filled bodies with outlines, plus detail strokes.
struct ChessPieceView: View {
    let piece: Chess.Piece
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            ChessPieceArt.draw(piece, in: &context, size: canvasSize.width)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum ChessPieceArt {
    enum Style { case body, detail, dot }

    struct Part {
        let path: Path
        let style: Style
    }

    struct Palette {
        let top: Color, bottom: Color, outline: Color, detail: Color, highlight: Color
    }

    static let whitePalette = Palette(top: Color(hex: 0xFFFDF8), bottom: Color(hex: 0xE4D8C4),
                                      outline: Color(hex: 0x2A1E15), detail: Color(hex: 0x2A1E15),
                                      highlight: .white.opacity(0.85))
    static let blackPalette = Palette(top: Color(hex: 0x57504A), bottom: Color(hex: 0x1D1916),
                                      outline: Color(hex: 0x0B0908), detail: Color(hex: 0xE8DCC8).opacity(0.75),
                                      highlight: .white.opacity(0.22))

    static func draw(_ piece: Chess.Piece, in context: inout GraphicsContext, size: CGFloat) {
        let palette = piece.side == .white ? whitePalette : blackPalette
        let scale = size / 100
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let line = max(1, 3.2 * scale)
        let gradient = Gradient(colors: [palette.top, palette.bottom])

        // Soft contact shadow.
        let shadowRect = CGRect(x: 20 * scale, y: 86 * scale, width: 60 * scale, height: 8 * scale)
        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.18)))

        for part in parts(piece.kind) {
            let path = part.path.applying(transform)
            switch part.style {
            case .body:
                let bounds = path.boundingRect
                context.fill(path, with: .linearGradient(gradient,
                                                         startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                                         endPoint: CGPoint(x: bounds.maxX * 0.4 + bounds.minX * 0.6, y: bounds.maxY)))
                context.stroke(path, with: .color(palette.outline),
                               style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            case .detail:
                context.stroke(path, with: .color(palette.detail),
                               style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round, lineJoin: .round))
            case .dot:
                context.fill(path, with: .color(palette.detail))
            }
        }
    }

    // MARK: Geometry

    private static func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private static func base() -> [Part] {
        [Part(path: roundRect(27, 73, 46, 8, 3), style: .body),
         Part(path: roundRect(20, 79, 60, 11, 5), style: .body)]
    }

    /// A flared pedestal from a narrow top (y = top) to the base line.
    private static func pedestal(top: CGFloat, topHalf: CGFloat, bottomHalf: CGFloat, bottom: CGFloat = 76) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 50 - topHalf, y: top))
            p.addQuadCurve(to: CGPoint(x: 50 - bottomHalf, y: bottom),
                           control: CGPoint(x: 50 - topHalf + 1, y: top + (bottom - top) * 0.72))
            p.addLine(to: CGPoint(x: 50 + bottomHalf, y: bottom))
            p.addQuadCurve(to: CGPoint(x: 50 + topHalf, y: top),
                           control: CGPoint(x: 50 + topHalf - 1, y: top + (bottom - top) * 0.72))
            p.closeSubpath()
        }
    }

    static func parts(_ kind: Chess.PieceKind) -> [Part] {
        switch kind {
        case .pawn: pawn
        case .knight: knight
        case .bishop: bishop
        case .rook: rook
        case .queen: queen
        case .king: king
        }
    }

    private static var pawn: [Part] {
        [Part(path: pedestal(top: 46, topHalf: 9, bottomHalf: 20), style: .body),
         Part(path: roundRect(34, 43, 32, 8, 4), style: .body),
         Part(path: circle(50, 30, 13.5), style: .body)]
            + [Part(path: roundRect(22, 77, 56, 12, 5), style: .body)]
    }

    private static var rook: [Part] {
        let top = Path { p in
            p.move(to: CGPoint(x: 27, y: 15))
            p.addLine(to: CGPoint(x: 37, y: 15))
            p.addLine(to: CGPoint(x: 37, y: 22))
            p.addLine(to: CGPoint(x: 45, y: 22))
            p.addLine(to: CGPoint(x: 45, y: 15))
            p.addLine(to: CGPoint(x: 55, y: 15))
            p.addLine(to: CGPoint(x: 55, y: 22))
            p.addLine(to: CGPoint(x: 63, y: 22))
            p.addLine(to: CGPoint(x: 63, y: 15))
            p.addLine(to: CGPoint(x: 73, y: 15))
            p.addLine(to: CGPoint(x: 73, y: 31))
            p.addLine(to: CGPoint(x: 67, y: 37))
            p.addLine(to: CGPoint(x: 33, y: 37))
            p.addLine(to: CGPoint(x: 27, y: 31))
            p.closeSubpath()
        }
        let body = Path { p in
            p.move(to: CGPoint(x: 34, y: 38))
            p.addLine(to: CGPoint(x: 66, y: 38))
            p.addLine(to: CGPoint(x: 69, y: 74))
            p.addLine(to: CGPoint(x: 31, y: 74))
            p.closeSubpath()
        }
        let detail = Path { p in
            p.move(to: CGPoint(x: 37, y: 47))
            p.addLine(to: CGPoint(x: 63, y: 47))
            p.move(to: CGPoint(x: 36, y: 65))
            p.addLine(to: CGPoint(x: 64, y: 65))
        }
        return [Part(path: body, style: .body),
                Part(path: top, style: .body),
                Part(path: roundRect(30, 35, 40, 6, 2), style: .body),
                Part(path: detail, style: .detail)] + base()
    }

    private static var bishop: [Part] {
        let mitre = Path { p in
            p.move(to: CGPoint(x: 50, y: 16))
            p.addCurve(to: CGPoint(x: 66, y: 40), control1: CGPoint(x: 58, y: 22), control2: CGPoint(x: 67, y: 30))
            p.addCurve(to: CGPoint(x: 50, y: 55), control1: CGPoint(x: 66, y: 49), control2: CGPoint(x: 59, y: 55))
            p.addCurve(to: CGPoint(x: 34, y: 40), control1: CGPoint(x: 41, y: 55), control2: CGPoint(x: 34, y: 49))
            p.addCurve(to: CGPoint(x: 50, y: 16), control1: CGPoint(x: 33, y: 30), control2: CGPoint(x: 42, y: 22))
            p.closeSubpath()
        }
        let slit = Path { p in
            p.move(to: CGPoint(x: 57, y: 29))
            p.addLine(to: CGPoint(x: 48, y: 40))
        }
        return [Part(path: pedestal(top: 56, topHalf: 9, bottomHalf: 19), style: .body),
                Part(path: mitre, style: .body),
                Part(path: slit, style: .detail),
                Part(path: roundRect(35, 53, 30, 7, 3.5), style: .body),
                Part(path: circle(50, 13, 5), style: .body)] + base()
    }

    private static var queen: [Part] {
        let crown = Path { p in
            p.move(to: CGPoint(x: 33, y: 60))
            p.addLine(to: CGPoint(x: 19, y: 28))
            p.addLine(to: CGPoint(x: 33, y: 43))
            p.addLine(to: CGPoint(x: 34, y: 22))
            p.addLine(to: CGPoint(x: 43, y: 40))
            p.addLine(to: CGPoint(x: 50, y: 18))
            p.addLine(to: CGPoint(x: 57, y: 40))
            p.addLine(to: CGPoint(x: 66, y: 22))
            p.addLine(to: CGPoint(x: 67, y: 43))
            p.addLine(to: CGPoint(x: 81, y: 28))
            p.addLine(to: CGPoint(x: 67, y: 60))
            p.closeSubpath()
        }
        let jewels: [Part] = [(19.0, 27.0), (34, 20.5), (50, 16.5), (66, 20.5), (81, 27)].map {
            Part(path: circle($0.0, $0.1, 4.6), style: .body)
        }
        return [Part(path: pedestal(top: 60, topHalf: 15, bottomHalf: 21), style: .body),
                Part(path: crown, style: .body)]
            + jewels
            + [Part(path: roundRect(31, 57, 38, 7, 3.5), style: .body)]
            + base()
    }

    private static var king: [Part] {
        let cross = Path { p in
            p.addRoundedRect(in: CGRect(x: 46, y: 5, width: 8, height: 22), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addRoundedRect(in: CGRect(x: 40, y: 10, width: 20, height: 7.5), cornerSize: CGSize(width: 1.5, height: 1.5))
        }
        let crown = Path { p in
            p.move(to: CGPoint(x: 34, y: 57))
            p.addCurve(to: CGPoint(x: 50, y: 30), control1: CGPoint(x: 20, y: 44), control2: CGPoint(x: 30, y: 26))
            p.addCurve(to: CGPoint(x: 66, y: 57), control1: CGPoint(x: 70, y: 26), control2: CGPoint(x: 80, y: 44))
            p.closeSubpath()
        }
        let crownDetail = Path { p in
            p.move(to: CGPoint(x: 50, y: 33))
            p.addLine(to: CGPoint(x: 50, y: 54))
        }
        let unionCross = cross.union(Path())
        return [Part(path: pedestal(top: 58, topHalf: 14, bottomHalf: 21), style: .body),
                Part(path: unionCross, style: .body),
                Part(path: crown, style: .body),
                Part(path: crownDetail, style: .detail),
                Part(path: roundRect(31, 54, 38, 7, 3.5), style: .body)] + base()
    }

    private static var knight: [Part] {
        let head = Path { p in
            p.move(to: CGPoint(x: 29, y: 75))
            // Chest
            p.addCurve(to: CGPoint(x: 43, y: 55), control1: CGPoint(x: 28, y: 66), control2: CGPoint(x: 34, y: 60))
            // Under the jaw
            p.addCurve(to: CGPoint(x: 25, y: 56), control1: CGPoint(x: 36, y: 54), control2: CGPoint(x: 30, y: 58))
            // Muzzle
            p.addCurve(to: CGPoint(x: 17, y: 46), control1: CGPoint(x: 20, y: 55), control2: CGPoint(x: 16, y: 51))
            p.addCurve(to: CGPoint(x: 23, y: 38), control1: CGPoint(x: 17, y: 42), control2: CGPoint(x: 20, y: 40))
            // Nose bridge and forehead
            p.addCurve(to: CGPoint(x: 39, y: 22), control1: CGPoint(x: 29, y: 33), control2: CGPoint(x: 33, y: 25))
            // Ear
            p.addLine(to: CGPoint(x: 42, y: 11))
            p.addCurve(to: CGPoint(x: 51, y: 20), control1: CGPoint(x: 46, y: 13), control2: CGPoint(x: 49, y: 16))
            // Back of the neck
            p.addCurve(to: CGPoint(x: 74, y: 40), control1: CGPoint(x: 62, y: 21), control2: CGPoint(x: 71, y: 29))
            p.addCurve(to: CGPoint(x: 72, y: 75), control1: CGPoint(x: 78, y: 52), control2: CGPoint(x: 74, y: 66))
            p.closeSubpath()
        }
        let mane = Path { p in
            p.move(to: CGPoint(x: 55, y: 25))
            p.addCurve(to: CGPoint(x: 67, y: 66), control1: CGPoint(x: 68, y: 34), control2: CGPoint(x: 70, y: 50))
            p.move(to: CGPoint(x: 31, y: 52))
            p.addQuadCurve(to: CGPoint(x: 38, y: 47), control: CGPoint(x: 35, y: 51))
        }
        return [Part(path: head, style: .body),
                Part(path: mane, style: .detail),
                Part(path: circle(36, 33, 3), style: .dot),
                Part(path: circle(22, 46, 1.8), style: .dot)] + base()
    }
}
