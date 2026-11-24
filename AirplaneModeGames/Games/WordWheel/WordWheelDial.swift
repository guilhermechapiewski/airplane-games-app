import SwiftUI
import GameLogic

/// Word Wheel colors. The game's indigo is used for the hub and accents; `ink` keeps text readable.
enum WordWheelPalette {
    static let accent = GameID.wordWheel.accent
    static let colors = GameID.wordWheel.colors
    /// Accent for text and strokes on the app background (lighter in dark mode).
    static let ink = Color(light: Color(hex: 0x4144B8), dark: Color(hex: 0xA9AFFF))
    /// Ring tiles.
    static let tile = Color(light: Color(hex: 0xEEF0FF), dark: Color(hex: 0x2A2E48))
    static let tileStroke = Color(light: Color(hex: 0xC9CDF5), dark: Color(hex: 0x41466B))
    /// The dial's face.
    static let face = Color(light: .white, dark: Color(hex: 0x1B1E2D))
    static let gold = Color(light: Color(hex: 0xB07A00), dark: Color(hex: 0xFFCF5C))
}

/// The letter wheel: a round dial with the required letter on the hub and six letters on the rim,
/// joined by spokes. Tapping a letter types it; Shuffle spins the rim letters to new places.
struct WordWheelDial: View {
    let model: WordWheelModel
    let puzzle: WordWheel.Puzzle
    let ring: [String]

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tile = side * 0.235
            let hub = side * 0.29
            let radius = side * 0.5 - tile * 0.5 - side * 0.035
            ZStack {
                face(side: side, radius: radius, hub: hub)
                ForEach(ring, id: \.self) { letter in
                    let angle = model.ringAngles[letter] ?? Double(ring.firstIndex(of: letter) ?? 0) * 60
                    LetterTile(letter: letter, isCenter: false, size: tile,
                               pulse: model.tapTokens[letter] ?? 0, enabled: model.canPlay,
                               reduceMotion: reduceMotion, differentiateWithoutColor: differentiateWithoutColor) {
                        model.type(Character(letter))
                    }
                    .modifier(OrbitEffect(angle: angle, radius: radius))
                }
                LetterTile(letter: puzzle.center, isCenter: true, size: hub,
                           pulse: model.tapTokens[puzzle.center] ?? 0, enabled: model.canPlay,
                           reduceMotion: reduceMotion, differentiateWithoutColor: differentiateWithoutColor) {
                    model.type(puzzle.centerLetter)
                }
                .accessibilitySortPriority(1)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: model.pangramToken) { view, s in
                    view.scaleEffect(s)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(CGFloat(reduceMotion ? 1 : 1.18), duration: 0.18)
                        SpringKeyframe(CGFloat(1), duration: 0.35)
                        LinearKeyframe(CGFloat(1), duration: 0.05)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78), value: model.ringAngles)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter wheel")
        .accessibilityIdentifier("wordWheelDial")
    }

    private func face(side: CGFloat, radius: CGFloat, hub: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(WordWheelPalette.face)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: side * 0.04, y: side * 0.015)
            Circle()
                .strokeBorder(WordWheelPalette.tileStroke.opacity(0.7), lineWidth: 1)
            // Spokes from the hub to each rim slot.
            Path { p in
                let c = CGPoint(x: side / 2, y: side / 2)
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3
                    p.move(to: CGPoint(x: c.x + sin(a) * hub * 0.5, y: c.y - cos(a) * hub * 0.5))
                    p.addLine(to: CGPoint(x: c.x + sin(a) * radius, y: c.y - cos(a) * radius))
                }
            }
            .stroke(WordWheelPalette.tileStroke, style: StrokeStyle(lineWidth: max(1.5, side * 0.006), lineCap: .round))
            // The rim track the letters ride on.
            Circle()
                .stroke(WordWheelPalette.tileStroke.opacity(0.8),
                        style: StrokeStyle(lineWidth: max(1, side * 0.004), dash: [2, side * 0.022]))
                .frame(width: radius * 2, height: radius * 2)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Places a view on a circle at `angle` degrees clockwise from the top, animating along the arc.
private struct OrbitEffect: ViewModifier, Animatable {
    var angle: Double
    let radius: CGFloat

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let r = angle * .pi / 180
        content.offset(x: CGFloat(sin(r)) * radius, y: -CGFloat(cos(r)) * radius)
    }
}

private struct LetterTile: View {
    let letter: String
    let isCenter: Bool
    let size: CGFloat
    let pulse: Int
    let enabled: Bool
    let reduceMotion: Bool
    let differentiateWithoutColor: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isCenter {
                    Circle()
                        .fill(LinearGradient(colors: WordWheelPalette.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    // A second ring marks the hub by shape too, not only by color.
                    Circle()
                        .strokeBorder(.white.opacity(0.85), lineWidth: max(2, size * 0.035))
                        .padding(size * 0.07)
                    if differentiateWithoutColor {
                        Circle()
                            .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: max(1.5, size * 0.02), dash: [3, 3]))
                            .padding(size * 0.15)
                    }
                } else {
                    Circle().fill(WordWheelPalette.tile)
                    Circle().strokeBorder(WordWheelPalette.tileStroke, lineWidth: max(1, size * 0.02))
                }
                Text(letter.uppercased())
                    .font(.system(size: size * (isCenter ? 0.46 : 0.44), weight: isCenter ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(isCenter ? Color.white : Color.primary)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: isCenter ? WordWheelPalette.accent.opacity(0.35) : .clear, radius: size * 0.08, y: size * 0.04)
            .contentShape(Circle())
            .keyframeAnimator(initialValue: CGFloat(1), trigger: pulse) { view, s in
                view.scaleEffect(s)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(CGFloat(reduceMotion ? 1 : 0.88), duration: 0.07)
                    SpringKeyframe(CGFloat(1), duration: 0.2)
                    LinearKeyframe(CGFloat(1), duration: 0.03)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(isCenter ? "\(letter.uppercased()), center letter" : letter.uppercased())
        .accessibilityHint(isCenter ? "Every word must use this letter" : "")
        .accessibilityIdentifier(isCenter ? "letter.center" : "letter.\(letter)")
    }
}
