import SwiftUI
import GameLogic

struct TileMatchView: View {
    @State private var model = TileMatchModel()
    @Environment(\.reduceMotion) private var reduceMotion

    private var accent: Color { GameID.tileMatch.accent }

    var body: some View {
        VStack(spacing: 12) {
            header
            TileMatchBoard(model: model, reduceMotion: reduceMotion, onTap: tap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay { overlay }
        .gameChrome(.tileMatch, rules: Self.rules,
                    stats: TileMatch.LayoutID.allCases.map {
                        StatsVariant(key: $0.rawValue, title: "\($0.title) · \($0.layout.tileCount) tiles", showsTime: true)
                    },
                    newGame: TileMatch.LayoutID.allCases.map { id in
                        NewGameOption(title: "\(id.title) · \(id.layout.tileCount)", systemImage: id.symbol) {
                            withAnimation(.easeOut(duration: 0.2)) { model.newGame(layout: id) }
                        }
                    },
                    onActiveChange: model.setActive)
    }

    private func tap(_ id: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72)) { model.tap(id) }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(spacing: 10) {
            StatPill(title: "Tiles", value: "\(model.tilesLeft)", tint: accent)
                .accessibilityIdentifier("tilesLeft")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                StatPill(title: "Time", value: model.clock.elapsed().clockString)
            }
            StatPill(title: "Moves", value: "\(model.availableMatches)")
                .accessibilityLabel("Available moves")
                .accessibilityValue("\(model.availableMatches)")
            Spacer(minLength: 0)
            // The layout name only shows when there is room for all of it.
            ViewThatFits(in: .horizontal) {
                Text(model.layout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("Layout \(model.layout.title)")
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .animation(.snappy, value: model.tilesLeft)
        .animation(.snappy, value: model.availableMatches)
    }

    private var controls: some View {
        HStack(spacing: 22) {
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { model.undo() }
            }
            .disabled(!model.canUndo)
            ToolButton(title: "Hint", systemImage: "lightbulb", isActive: model.hint != nil, tint: Color(hex: 0xE5A100)) {
                withAnimation(.easeOut(duration: 0.2)) { model.showHint() }
            }
            .disabled(model.showWin || model.tilesLeft == 0)
            ToolButton(title: "Shuffle", systemImage: "shuffle") { shuffle() }
                .disabled(model.showWin || model.tilesLeft < 2)
            ToolButton(title: "New", systemImage: "arrow.clockwise") {
                withAnimation(.easeOut(duration: 0.2)) { model.newGame() }
            }
        }
    }

    private func shuffle() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.8)) {
            model.shuffle()
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlay: some View {
        if model.showWin {
            ResultOverlay(mood: .win, title: "Board Cleared!",
                          subtitle: model.lastWinWasBest ? "New best time on \(model.layout.title)!" : "\(model.layout.title) · \(model.layout.layout.tileCount) tiles",
                          details: [("Time", model.clock.elapsed().clockString),
                                    ("Best", model.bestTime?.clockString ?? "–")],
                          tint: accent) {
                Button("Play Again") { withAnimation { model.newGame() } }
                    .buttonStyle(PrimaryButtonStyle(color: accent))
                Menu {
                    ForEach(TileMatch.LayoutID.allCases) { id in
                        Button { withAnimation { model.newGame(layout: id) } } label: {
                            Label("\(id.title) · \(id.layout.tileCount)", systemImage: id.symbol)
                        }
                    }
                } label: {
                    Text("Other Layout")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .transition(.opacity)
        } else if model.showStuck {
            ResultOverlay(mood: .neutral, title: "No moves left",
                          subtitle: model.stuckIsHopeless
                            ? "These tiles can’t be paired in any arrangement. Undo a few moves or start over."
                            : "Shuffle the remaining tiles to keep going.",
                          details: [("Tiles", "\(model.tilesLeft)")],
                          tint: accent) {
                if !model.stuckIsHopeless {
                    Button { shuffle() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(PrimaryButtonStyle(color: accent))
                }
                HStack(spacing: 10) {
                    Button("Undo") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.undo() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canUndo)
                    Button("New Game") { withAnimation { model.newGame() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.opacity.animation(.easeOut(duration: 0.25).delay(reduceMotion ? 0 : 0.45)))
        }
    }

    static let rules = HowToPlay(
        summary: "Clear the stack by matching pairs of free tiles.",
        sections: [
            .init(title: "Free tiles", symbol: "square.stack.3d.up", points: [
                "A tile is free when nothing lies on top of it and its left or right side is open.",
                "Free tiles look bright; blocked tiles are slightly dimmed.",
            ]),
            .init(title: "Matching", symbol: "rectangle.on.rectangle", points: [
                "Tap a free tile, then a free tile with the same face to remove both.",
                "Ocean, Forest and Ember tiles match the same suit and number.",
                "Any two Treasures (dashed gold frame) match, and so do any two Critters.",
            ]),
            .init(title: "Help", symbol: "lightbulb", points: [
                "Every deal can be cleared. Hint shows a pair that keeps the board solvable when it can.",
                "Stuck? Shuffle rearranges the remaining tiles so the board can be cleared again.",
                "Undo takes back matches and shuffles, as many as you like.",
            ]),
            .init(title: "Layouts", symbol: "square.grid.3x3", points: [
                "Choose a layout from New Game. Pebble is quick; Fortress uses all 144 tiles.",
                "Your best time is kept for each layout.",
            ]),
        ]
    )
}

extension TileMatch.LayoutID {
    var symbol: String {
        switch self {
        case .pebble: "circle.grid.2x2"
        case .lantern: "lamp.ceiling"
        case .pyramid: "triangle"
        case .bridge: "road.lanes"
        case .butterfly: "sparkles"
        case .fortress: "building.columns"
        }
    }
}

// MARK: - Board

/// Maps layout slots to screen points. Tiles are `tileW × tileH`, each layer is shifted up-left
/// by `depth`, and every tile shows a raised edge of `depth` on its bottom-right.
struct BoardGeometry {
    let tileW: CGFloat
    let tileH: CGFloat
    let depth: CGFloat
    let size: CGSize
    private let minX: Int
    private let minY: Int
    private let maxZ: Int

    static let aspect: CGFloat = 1.3
    static let depthRatio: CGFloat = 0.13

    init(layout: TileMatch.Layout, fitting available: CGSize) {
        let b = layout.bounds
        let cols = CGFloat(b.width) / 2, rows = CGFloat(b.height) / 2
        let extra = Self.depthRatio * CGFloat(layout.maxZ + 1)
        let w = max(8, min(available.width / (cols + extra),
                           available.height / (rows * Self.aspect + extra),
                           96))
        tileW = w
        tileH = w * Self.aspect
        depth = w * Self.depthRatio
        minX = b.minX
        minY = b.minY
        maxZ = layout.maxZ
        size = CGSize(width: cols * w + extra * w, height: rows * tileH + extra * w)
    }

    /// Top-left corner of a tile's face.
    func origin(_ p: TileMatch.Position) -> CGPoint {
        let lift = CGFloat(maxZ - p.z) * depth
        return CGPoint(x: CGFloat(p.x - minX) / 2 * tileW + lift, y: CGFloat(p.y - minY) / 2 * tileH + lift)
    }

    func center(_ p: TileMatch.Position) -> CGPoint {
        let o = origin(p)
        return CGPoint(x: o.x + tileW / 2, y: o.y + tileH / 2)
    }
}

private struct TileMatchBoard: View {
    let model: TileMatchModel
    let reduceMotion: Bool
    let onTap: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let geo = BoardGeometry(layout: model.layout.layout, fitting: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.state.tiles.enumerated()), id: \.element.id) { rank, tile in
                    tileView(tile, rank: rank, geo: geo)
                        .id("\(model.dealToken).\(tile.id)")
                }
                ForEach(model.vanishing) { v in
                    VanishingTile(tile: v.tile, partner: v.partner, geo: geo, reduceMotion: reduceMotion)
                        .zIndex(1000)
                }
                ForEach(model.vanishing.filter { $0.tile.id < $0.partner.id }) { v in
                    let a = geo.center(v.tile.position), b = geo.center(v.partner.position)
                    SparkleBurst(size: geo.tileW * 2.2, reduceMotion: reduceMotion)
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        .zIndex(1001)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board, \(model.tilesLeft) tiles left")
        .accessibilityIdentifier("tileMatchBoard")
    }

    @ViewBuilder
    private func tileView(_ tile: TileMatch.Tile, rank: Int, geo: BoardGeometry) -> some View {
        let id = tile.id
        let free = model.freeIDs.contains(id)
        let selected = model.selected == id
        let hinted = model.hint?.contains(id) ?? false
        let uncovered = model.uncoveredIDs.contains(id)
        let origin = geo.origin(tile.position)
        let traits: AccessibilityTraits = selected ? [.isButton, .isSelected] : .isButton
        let order = -Double(tile.position.y * 1000 + tile.position.x)
        TileView(face: tile.face, geo: geo, isFree: free, isSelected: selected, isHinted: hinted,
                 shakeTrigger: model.shakeTokens[id] ?? 0, reduceMotion: reduceMotion)
            .offset(x: origin.x, y: origin.y)
            .zIndex(Double(rank) + (selected ? 500 : 0))
            .transition(transition(rank: rank, geo: geo))
            .onTapGesture { onTap(id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FaceStyle.of(tile.face).name)
            .accessibilityValue(accessibilityValue(free: free, selected: selected, hinted: hinted))
            .accessibilityAddTraits(traits)
            .accessibilityHint(free ? "Double-tap to select or match." : "Blocked. Free its left or right side first.")
            .accessibilityAction { onTap(id) }
            .accessibilityHidden(!uncovered)
            .accessibilityIdentifier("tile.\(id)")
            .accessibilitySortPriority(order)
    }

    private func transition(rank: Int, geo: BoardGeometry) -> AnyTransition {
        guard model.isDealing, !reduceMotion else {
            return .asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .identity)
        }
        let delay = 0.5 * Double(rank) / Double(max(1, model.tilesLeft))
        let insertion = AnyTransition.offset(y: -geo.tileH * 0.6).combined(with: .opacity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay))
        return .asymmetric(insertion: insertion, removal: .identity)
    }

    private func accessibilityValue(free: Bool, selected: Bool, hinted: Bool) -> String {
        var parts = [free ? "free" : "blocked"]
        if selected { parts.append("selected") }
        if hinted { parts.append("hinted") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tile

/// A rounded rectangle swept diagonally by `depth`: the face plus its raised edge.
private struct TileSlab: Shape {
    var depth: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width - depth, h = rect.height - depth
        let r = min(cornerRadius, w / 2, h / 2)
        let face = CGRect(x: rect.minX, y: rect.minY, width: w, height: h)
        var p = Path(roundedRect: face, cornerRadius: r, style: .continuous)
        p = p.union(Path(roundedRect: face.offsetBy(dx: depth, dy: depth), cornerRadius: r, style: .continuous))
        // Bridge the two rectangles along the tangents of the top-right and bottom-left corners.
        let s = r * 0.7071
        let tr = CGPoint(x: face.maxX - r + s, y: face.minY + r - s)
        let bl = CGPoint(x: face.minX + r - s, y: face.maxY - r + s)
        var bridge = Path()
        bridge.addLines([tr, CGPoint(x: tr.x + depth, y: tr.y + depth),
                         CGPoint(x: bl.x + depth, y: bl.y + depth), bl])
        bridge.closeSubpath()
        return p.union(bridge)
    }
}

private struct TileView: View {
    let face: TileMatch.Face
    let geo: BoardGeometry
    let isFree: Bool
    let isSelected: Bool
    let isHinted: Bool
    let shakeTrigger: Int
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let w = geo.tileW, h = geo.tileH, d = geo.depth
        let radius = w * 0.14
        let accent = GameID.tileMatch.accent
        let palette = TilePalette(dark: scheme == .dark)
        ZStack(alignment: .topLeading) {
            // Coloured back, then the ivory body, then the face.
            TileSlab(depth: d, cornerRadius: radius)
                .fill(LinearGradient(colors: palette.back, startPoint: .topLeading, endPoint: .bottomTrailing))
            TileSlab(depth: d * 0.55, cornerRadius: radius)
                .fill(palette.body)
                .frame(width: w + d * 0.55, height: h + d * 0.55)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: isFree ? palette.faceFree : palette.faceBlocked,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(palette.rim, lineWidth: max(0.5, w * 0.02))
                }
                .overlay {
                    TileFaceArt(face: face, width: w)
                        .opacity(isFree ? 1 : 0.72)
                        .saturation(isFree ? 1 : 0.75)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(accent.opacity(0.12))
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(accent, lineWidth: max(2, w * 0.06))
                    } else if isHinted {
                        HintRing(radius: radius, width: max(2, w * 0.06), reduceMotion: reduceMotion)
                    }
                }
                .frame(width: w, height: h)
        }
        .frame(width: w + d, height: h + d, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: isSelected ? accent.opacity(0.55) : .black.opacity(scheme == .dark ? 0.45 : 0.22),
                radius: isSelected ? d * 2 : d * 0.7, x: d * 0.35, y: d * 0.55)
        .scaleEffect(isSelected && !reduceMotion ? 1.05 : 1)
        .offset(y: isSelected && !reduceMotion ? -d * 0.8 : 0)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shakeTrigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let a = reduceMotion ? 0 : w * 0.09
            KeyframeTrack {
                LinearKeyframe(-a, duration: 0.05)
                LinearKeyframe(a, duration: 0.08)
                LinearKeyframe(-a * 0.6, duration: 0.07)
                LinearKeyframe(a * 0.3, duration: 0.06)
                LinearKeyframe(0, duration: 0.05)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct TilePalette {
    let back: [Color]
    let body: Color
    let faceFree: [Color]
    let faceBlocked: [Color]
    let rim: Color

    init(dark: Bool) {
        if dark {
            back = [Color(hex: 0xC2456B), Color(hex: 0x8E2A4C)]
            body = Color(hex: 0xCDBF9F)
            faceFree = [Color(hex: 0xFBF6EA), Color(hex: 0xEAE0CB)]
            faceBlocked = [Color(hex: 0xCFC6B3), Color(hex: 0xBDB39E)]
            rim = Color(hex: 0xFFFFFF, opacity: 0.55)
        } else {
            back = [Color(hex: 0xEE6F92), Color(hex: 0xC93F67)]
            body = Color(hex: 0xE9DCC0)
            faceFree = [Color(hex: 0xFFFEF8), Color(hex: 0xF5EDDB)]
            faceBlocked = [Color(hex: 0xE9E3D5), Color(hex: 0xDCD3C0)]
            rim = Color(hex: 0xFFFFFF, opacity: 0.9)
        }
    }
}

private struct HintRing: View {
    let radius: CGFloat
    let width: CGFloat
    let reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        let gold = Color(hex: 0xF2B300)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(gold.opacity(glow ? 0.22 : 0.08))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(gold, lineWidth: width)
            }
            .opacity(glow ? 1 : 0.55)
            .onAppear {
                guard !reduceMotion else { glow = true; return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

// MARK: - Match effects

/// A matched tile flying toward its partner while it shrinks and fades.
private struct VanishingTile: View {
    let tile: TileMatch.Tile
    let partner: TileMatch.Tile
    let geo: BoardGeometry
    let reduceMotion: Bool
    @State private var gone = false

    var body: some View {
        let from = geo.origin(tile.position)
        let a = geo.center(tile.position), b = geo.center(partner.position)
        let travel = reduceMotion ? CGSize.zero : CGSize(width: (b.x - a.x) / 2, height: (b.y - a.y) / 2)
        TileView(face: tile.face, geo: geo, isFree: true, isSelected: false, isHinted: false,
                 shakeTrigger: 0, reduceMotion: true)
            .scaleEffect(gone ? (reduceMotion ? 1 : 0.5) : 1.04)
            .opacity(gone ? 0 : 1)
            .offset(x: from.x + (gone ? travel.width : 0), y: from.y + (gone ? travel.height : 0) - (gone ? 0 : geo.depth))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.3)) { gone = true }
            }
    }
}

/// A short burst of sparkles where a pair meets.
private struct SparkleBurst: View {
    let size: CGFloat
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, canvas in
                    let t = timeline.date.timeIntervalSince(start) - 0.18
                    guard t > 0, t < 0.5 else { return }
                    let p = t / 0.5
                    let mid = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    let colors: [Color] = [Color(hex: 0xFFC94A), Color(hex: 0xFF8FA3), .white, Color(hex: 0x7FD3FF)]
                    for i in 0..<12 {
                        let angle = Double(i) / 12 * 2 * .pi + 0.3
                        let dist = (0.15 + 0.85 * (1 - pow(1 - p, 2))) * Double(canvas.width) * (i.isMultiple(of: 2) ? 0.45 : 0.32)
                        let pt = CGPoint(x: mid.x + cos(angle) * dist, y: mid.y + sin(angle) * dist)
                        let s = (1 - p) * Double(canvas.width) * (i.isMultiple(of: 2) ? 0.09 : 0.06)
                        var c = ctx
                        c.opacity = 1 - p * p
                        c.translateBy(x: pt.x, y: pt.y)
                        c.rotate(by: .radians(p * 2))
                        c.fill(Self.star(size: s), with: .color(colors[i % colors.count]))
                    }
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start = .now }
        }
    }

    /// Four-pointed sparkle centred on the origin.
    static func star(size s: Double) -> Path {
        var p = Path()
        let k = s * 0.22
        p.move(to: CGPoint(x: 0, y: -s))
        p.addQuadCurve(to: CGPoint(x: s, y: 0), control: CGPoint(x: k, y: -k))
        p.addQuadCurve(to: CGPoint(x: 0, y: s), control: CGPoint(x: k, y: k))
        p.addQuadCurve(to: CGPoint(x: -s, y: 0), control: CGPoint(x: -k, y: k))
        p.addQuadCurve(to: CGPoint(x: 0, y: -s), control: CGPoint(x: -k, y: -k))
        return p
    }
}
