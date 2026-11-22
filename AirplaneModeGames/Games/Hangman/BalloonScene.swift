import SwiftUI

/// Hangman's illustration: a little basket carried by a bunch of balloons.
/// Each miss lets one balloon float away and the basket drifts lower; when the last
/// one is gone the basket settles gently on the meadow. Winning lifts it into the sky.
struct BalloonScene: View {
    /// Balloons still attached (0...6).
    let balloons: Int
    let won: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var sway = false
    @State private var drift = false

    static let total = 6
    static let colors: [Color] = [
        Color(hex: 0xFF6F61), Color(hex: 0x5AA9FF), Color(hex: 0xFFC94A),
        Color(hex: 0x3CC8B4), Color(hex: 0xB48CFF), Color(hex: 0xFF8FB8),
    ]
    /// Balloon centers relative to the basket's top center, in units of scene height.
    private static let offsets: [CGPoint] = [
        CGPoint(x: 0, y: -0.3), CGPoint(x: -0.16, y: -0.25), CGPoint(x: 0.16, y: -0.25),
        CGPoint(x: -0.09, y: -0.38), CGPoint(x: 0.09, y: -0.38), CGPoint(x: 0, y: -0.47),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, u = geo.size.height
            let groundY = u * 0.86
            let basketW = u * 0.2, basketH = u * 0.11
            let misses = CGFloat(Self.total - balloons)
            let floatTop = u * 0.55
            let landedTop = groundY - basketH + u * 0.015
            let top = won ? -u * 0.2 : floatTop + (landedTop - floatTop) * misses / CGFloat(Self.total)
            let center = CGPoint(x: w / 2, y: top)

            ZStack {
                sky(width: w, height: u)
                clouds(width: w, height: u)
                hills(width: w, height: u, groundY: groundY)

                // Basket + balloons travel together.
                ZStack {
                    strings(center: center, u: u, basketW: basketW)
                    ForEach(0..<balloons, id: \.self) { i in
                        let o = Self.offsets[i]
                        BalloonShape(color: Self.colors[i])
                            .frame(width: u * 0.14, height: u * 0.17)
                            .position(x: center.x + o.x * u, y: center.y + o.y * u)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity),
                                removal: .offset(y: -u * 0.5).combined(with: .scale(scale: 0.6)).combined(with: .opacity)))
                    }
                    Basket()
                        .frame(width: basketW, height: basketH)
                        .position(x: center.x, y: top + basketH / 2)
                }
                .rotationEffect(.degrees(sway && balloons > 0 && !reduceMotion ? 1.6 : -1.6),
                                anchor: UnitPoint(x: 0.5, y: max(0, min(1, (top + basketH) / u))))
                .animation(reduceMotion ? nil : .spring(response: won ? 1.4 : 0.7, dampingFraction: 0.8), value: balloons)
                .animation(reduceMotion ? nil : .easeIn(duration: 1.6), value: won)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { sway = true }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(won ? "The balloons carry the basket up into the sky"
            : balloons == 0 ? "The basket has landed. No balloons left"
            : "Basket carried by \(balloons) \(balloons == 1 ? "balloon" : "balloons")")
    }

    private var isDark: Bool { colorScheme == .dark }

    private func sky(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: isDark ? [Color(hex: 0x16203A), Color(hex: 0x2A3D63)]
                                          : [Color(hex: 0x9FD6FF), Color(hex: 0xE4F4FF)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(isDark ? Color(hex: 0xF3F0D8) : Color(hex: 0xFFD45E))
                .frame(width: height * 0.13, height: height * 0.13)
                .shadow(color: (isDark ? Color.white : Color.yellow).opacity(0.5), radius: height * 0.05)
                .padding(.top, height * 0.08)
                .padding(.trailing, width * 0.08)
            if isDark {
                ForEach(0..<9, id: \.self) { i in
                    Circle().fill(.white.opacity(0.7))
                        .frame(width: 2.5, height: 2.5)
                        .position(x: width * [0.1, 0.22, 0.35, 0.48, 0.6, 0.7, 0.15, 0.42, 0.82][i],
                                  y: height * [0.1, 0.24, 0.08, 0.18, 0.06, 0.3, 0.4, 0.34, 0.42][i])
                }
            }
        }
    }

    private func clouds(width: CGFloat, height: CGFloat) -> some View {
        let tint = isDark ? Color(hex: 0x3A4A6E) : Color.white.opacity(0.9)
        return ZStack {
            Cloud().fill(tint)
                .frame(width: height * 0.36, height: height * 0.13)
                .position(x: width * 0.2 + (drift ? 14 : -14), y: height * 0.2)
            Cloud().fill(tint)
                .frame(width: height * 0.28, height: height * 0.1)
                .position(x: width * 0.8 + (drift ? -10 : 10), y: height * 0.45)
        }
    }

    private func hills(width: CGFloat, height: CGFloat, groundY: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(isDark ? Color(hex: 0x24493A) : Color(hex: 0x8FD18B))
                .frame(width: width * 0.9, height: height * 0.34)
                .position(x: width * 0.2, y: groundY + height * 0.1)
            Ellipse()
                .fill(isDark ? Color(hex: 0x2E5A43) : Color(hex: 0x6CBF74))
                .frame(width: width * 1.1, height: height * 0.3)
                .position(x: width * 0.78, y: groundY + height * 0.12)
            ForEach(0..<5, id: \.self) { i in
                Flower(color: Self.colors[(i * 2) % Self.colors.count])
                    .frame(width: height * 0.035, height: height * 0.035)
                    .position(x: width * [0.08, 0.3, 0.62, 0.86, 0.94][i],
                              y: groundY + height * [0.05, 0.08, 0.06, 0.04, 0.09][i])
            }
        }
    }

    private func strings(center: CGPoint, u: CGFloat, basketW: CGFloat) -> some View {
        Path { path in
            for i in 0..<balloons {
                let o = Self.offsets[i]
                let knot = CGPoint(x: center.x + o.x * u, y: center.y + o.y * u + u * 0.085)
                let anchor = CGPoint(x: center.x + (o.x < 0 ? -1 : o.x > 0 ? 1 : 0) * basketW * 0.3, y: center.y)
                path.move(to: knot)
                path.addQuadCurve(to: anchor, control: CGPoint(x: (knot.x + anchor.x) / 2 + u * 0.01,
                                                                y: (knot.y + anchor.y) / 2))
            }
        }
        .stroke(isDark ? Color.white.opacity(0.55) : Color(hex: 0x5D6577).opacity(0.7), lineWidth: 1.2)
    }
}

private struct BalloonShape: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [color.opacity(0.75), color],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.7))
                    .frame(width: w, height: h * 0.88)
                    .position(x: w / 2, y: h * 0.44)
                Ellipse()
                    .fill(.white.opacity(0.55))
                    .frame(width: w * 0.18, height: h * 0.2)
                    .rotationEffect(.degrees(-25))
                    .position(x: w * 0.32, y: h * 0.26)
                Triangle()
                    .fill(color)
                    .frame(width: w * 0.16, height: h * 0.08)
                    .position(x: w / 2, y: h * 0.91)
            }
        }
    }
}

private struct Basket: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                BasketBody()
                    .fill(LinearGradient(colors: [Color(hex: 0xD99A5B), Color(hex: 0xB0743E)],
                                         startPoint: .top, endPoint: .bottom))
                BasketBody()
                    .stroke(Color(hex: 0x8A5428), lineWidth: 1)
                ForEach(1..<3, id: \.self) { i in
                    Rectangle()
                        .fill(Color(hex: 0x8A5428).opacity(0.45))
                        .frame(width: w * (0.9 - CGFloat(i) * 0.05), height: 1.2)
                        .position(x: w / 2, y: h * CGFloat(i) * 0.3 + h * 0.1)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x8A5428))
                    .frame(width: w * 1.04, height: h * 0.18)
                    .position(x: w / 2, y: h * 0.06)
                // A little paper-plane pennant.
                Triangle()
                    .fill(GameID.hangman.accent)
                    .frame(width: w * 0.22, height: h * 0.32)
                    .rotationEffect(.degrees(90))
                    .position(x: w * 0.8, y: -h * 0.22)
                Rectangle()
                    .fill(Color(hex: 0x8A5428))
                    .frame(width: 1.5, height: h * 0.55)
                    .position(x: w * 0.7, y: -h * 0.15)
            }
        }
    }
}

private struct BasketBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Cloud: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + h * 0.45, width: rect.width, height: h * 0.55),
                         cornerSize: CGSize(width: h * 0.27, height: h * 0.27))
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + h * 0.15, width: h * 0.75, height: h * 0.75))
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.42, y: rect.minY, width: h * 0.95, height: h * 0.95))
        return p
    }
}

private struct Flower: View {
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: -3)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(Color(hex: 0xFFF2B3)).frame(width: 3.5, height: 3.5)
        }
    }
}
