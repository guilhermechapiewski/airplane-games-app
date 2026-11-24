import SwiftUI
import GameLogic

/// The minefield: fits the screen initially and supports pinch-to-zoom and panning.
///
/// A single board-level gesture interprets touches as tap, long press or pan, which keeps
/// tapping responsive while zoomed and avoids per-cell gesture conflicts.
struct MinesweeperBoard: View {
    let model: MinesweeperModel
    @Binding var zoomRequest: ZoomRequest?
    var onZoomableChange: (Bool, Bool) -> Void = { _, _ in }

    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var zoom: CGFloat = 1
    @State private var offset: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var pinchScale: CGFloat = 1
    @State private var pinchAnchor: CGPoint = .zero
    @State private var touch: Touch?
    @State private var touchCounter = 0
    @GestureState private var touchActive = false

    /// A comfortable tap target when zoomed in.
    static let comfortableCell: CGFloat = 40
    private static let maxFitCell: CGFloat = 52
    private static let wellPadding: CGFloat = 6

    private struct Touch {
        let id: Int
        let start: CGPoint
        var panning = false
        var longPressed = false
        var cancelled = false
    }

    enum ZoomRequest: Equatable { case fit, comfortable }

    var body: some View {
        GeometryReader { geo in
            let pad = Self.wellPadding
            let viewport = CGSize(width: max(0, geo.size.width - pad * 2), height: max(0, geo.size.height - pad * 2))
            let fit = fitCell(in: viewport)
            // Boards that already fit with comfortable cells don't zoom.
            let maxZoom = fit >= Self.comfortableCell * 0.85 ? 1 : Self.comfortableCell * 1.25 / fit
            let cell = fit * zoom
            let boardSize = size(for: cell)
            let shown = displayedOffset(viewport: viewport, boardSize: boardSize)
            let visible = CGRect(x: shown.x, y: shown.y, width: boardSize.width * pinchScale, height: boardSize.height * pinchScale)
                .intersection(CGRect(origin: .zero, size: viewport))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.well)
                    .frame(width: max(0, visible.width) + pad * 2, height: max(0, visible.height) + pad * 2)
                    .offset(x: visible.isNull ? 0 : visible.minX, y: visible.isNull ? 0 : visible.minY)

                MinefieldGrid(state: model.state, cell: cell, revealDelays: model.revealDelays,
                              explosionDelays: model.explosionDelays, reduceMotion: reduceMotion,
                              model: model)
                    .equatable()
                    .frame(width: boardSize.width, height: boardSize.height)
                    .overlay(alignment: .topLeading) {
                        if let hint = model.hint {
                            HintHighlight(hint: hint, cell: cell, reduceMotion: reduceMotion)
                                .transition(.opacity)
                        }
                    }
                    .scaleEffect(pinchScale, anchor: .topLeading)
                    .offset(x: shown.x, y: shown.y)
                    .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius - pad, style: .continuous))
                    .gesture(touchGesture(cell: cell, viewport: viewport, boardSize: boardSize), including: voiceOver ? .subviews : .all)
                    .onGestureCancelled(touchActive) {
                        // A cancelled touch neither taps nor flags; an unfinished pan springs back.
                        touch = nil
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { dragTranslation = .zero }
                    }
                    .padding(pad)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .simultaneousGesture(magnifyGesture(fit: fit, maxZoom: maxZoom, viewport: viewport))
                .onChange(of: zoomRequest) { _, request in
                    guard let request else { return }
                    let target = request == .fit ? 1 : min(maxZoom, Self.comfortableCell / fit)
                    zoom(to: target, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2),
                         fit: fit, viewport: viewport)
                    zoomRequest = nil
                }
                .onChange(of: model.boardID) { _, _ in
                    zoom = 1
                    offset = .zero
                }
                .onChange(of: voiceOver) { _, on in if on { zoom = 1 } }
                .onAppear { report(fit: fit, maxZoom: maxZoom) }
                .onChange(of: zoom) { _, _ in report(fit: fit, maxZoom: maxZoom) }
                .onChange(of: fit) { _, _ in report(fit: fit, maxZoom: maxZoom) }
        }
    }

    private func report(fit: CGFloat, maxZoom: CGFloat) {
        guard fit > 1 else { return }
        onZoomableChange(maxZoom > 1.05, zoom > 1.05)
    }

    // MARK: Geometry

    private func fitCell(in viewport: CGSize) -> CGFloat {
        let s = model.state
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(Self.maxFitCell, viewport.width / CGFloat(s.cols), viewport.height / CGFloat(s.rows)).rounded(.down)
    }

    private func size(for cell: CGFloat) -> CGSize {
        CGSize(width: cell * CGFloat(model.state.cols), height: cell * CGFloat(model.state.rows))
    }

    /// Centers small boards; keeps large boards inside the viewport.
    private func clamp(_ o: CGPoint, viewport: CGSize, boardSize: CGSize) -> CGPoint {
        func axis(_ v: CGFloat, _ view: CGFloat, _ board: CGFloat) -> CGFloat {
            board <= view ? (view - board) / 2 : min(0, max(view - board, v))
        }
        return CGPoint(x: axis(o.x, viewport.width, boardSize.width), y: axis(o.y, viewport.height, boardSize.height))
    }

    private func displayedOffset(viewport: CGSize, boardSize: CGSize) -> CGPoint {
        if pinchScale != 1 {
            let scaled = CGSize(width: boardSize.width * pinchScale, height: boardSize.height * pinchScale)
            let base = clamp(offset, viewport: viewport, boardSize: boardSize)
            let o = CGPoint(x: pinchAnchor.x - (pinchAnchor.x - base.x) * pinchScale,
                            y: pinchAnchor.y - (pinchAnchor.y - base.y) * pinchScale)
            return clamp(o, viewport: viewport, boardSize: scaled)
        }
        let o = CGPoint(x: offset.x + dragTranslation.width, y: offset.y + dragTranslation.height)
        return clamp(o, viewport: viewport, boardSize: boardSize)
    }

    private func zoom(to target: CGFloat, around anchor: CGPoint, fit: CGFloat, viewport: CGSize) {
        let base = clamp(offset, viewport: viewport, boardSize: size(for: fit * zoom))
        let ratio = target / zoom
        let o = CGPoint(x: anchor.x - (anchor.x - base.x) * ratio, y: anchor.y - (anchor.y - base.y) * ratio)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            zoom = target
            offset = clamp(o, viewport: viewport, boardSize: size(for: fit * target))
        }
    }

    private func point(at location: CGPoint, cell: CGFloat, viewport: CGSize, boardSize: CGSize) -> GridPoint? {
        let o = displayedOffset(viewport: viewport, boardSize: boardSize)
        let col = Int(((location.x - o.x) / cell).rounded(.down))
        let row = Int(((location.y - o.y) / cell).rounded(.down))
        let p = GridPoint(row: row, col: col)
        return model.state.contains(p) ? p : nil
    }

    // MARK: Gestures

    private func touchGesture(cell: CGFloat, viewport: CGSize, boardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .tracking($touchActive)
            .onChanged { value in
                if touch == nil {
                    touchCounter += 1
                    touch = Touch(id: touchCounter, start: value.startLocation)
                    scheduleLongPress(id: touchCounter, cell: cell, viewport: viewport, boardSize: boardSize)
                }
                guard var t = touch, !t.cancelled else { return }
                if pinchScale != 1 { t.cancelled = true; touch = t; dragTranslation = .zero; return }
                let distance = hypot(value.translation.width, value.translation.height)
                if !t.panning && !t.longPressed && distance > 10 {
                    t.panning = true
                    touch = t
                }
                if t.panning {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                defer { touch = nil }
                guard let t = touch else { return }
                if t.panning {
                    let predicted = CGPoint(x: offset.x + value.predictedEndTranslation.width,
                                            y: offset.y + value.predictedEndTranslation.height)
                    let current = CGPoint(x: offset.x + value.translation.width, y: offset.y + value.translation.height)
                    offset = clamp(current, viewport: viewport, boardSize: boardSize)
                    dragTranslation = .zero
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                        offset = clamp(predicted, viewport: viewport, boardSize: boardSize)
                    }
                } else if !t.longPressed && !t.cancelled,
                          let p = point(at: t.start, cell: cell, viewport: viewport, boardSize: boardSize) {
                    model.tap(p)
                }
            }
    }

    private func scheduleLongPress(id: Int, cell: CGFloat, viewport: CGSize, boardSize: CGSize) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard var t = touch, t.id == id, !t.panning, !t.cancelled, pinchScale == 1,
                  let p = point(at: t.start, cell: cell, viewport: viewport, boardSize: boardSize) else { return }
            t.longPressed = true
            touch = t
            model.longPress(p)
        }
    }

    private func magnifyGesture(fit: CGFloat, maxZoom: CGFloat, viewport: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                guard maxZoom > 1.05 else { return }
                if pinchScale == 1 {
                    // The gesture is attached outside the well padding; convert to viewport space.
                    pinchAnchor = CGPoint(x: value.startLocation.x - Self.wellPadding,
                                          y: value.startLocation.y - Self.wellPadding)
                }
                let target = min(maxZoom, max(1, zoom * value.magnification))
                pinchScale = target / zoom
                if var t = touch { t.cancelled = true; touch = t }
                dragTranslation = .zero
            }
            .onEnded { _ in
                guard pinchScale != 1 else { return }
                let s = pinchScale
                let base = clamp(offset, viewport: viewport, boardSize: size(for: fit * zoom))
                let o = CGPoint(x: pinchAnchor.x - (pinchAnchor.x - base.x) * s,
                                y: pinchAnchor.y - (pinchAnchor.y - base.y) * s)
                let newZoom = zoom * s
                offset = clamp(o, viewport: viewport, boardSize: size(for: fit * newZoom))
                zoom = newZoom
                pinchScale = 1
            }
    }
}

// MARK: - Grid

private struct MinefieldGrid: View, Equatable {
    let state: Minesweeper.State
    let cell: CGFloat
    let revealDelays: [GridPoint: Double]
    let explosionDelays: [GridPoint: Double]
    let reduceMotion: Bool
    let model: MinesweeperModel

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.state == b.state && a.cell == b.cell && a.revealDelays == b.revealDelays
            && a.explosionDelays == b.explosionDelays && a.reduceMotion == b.reduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<state.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<state.cols, id: \.self) { c in
                        let p = GridPoint(row: r, col: c)
                        MineCellView(cell: state[p], status: state.status, isExploded: state.exploded == p,
                                     size: cell, revealDelay: reduceMotion ? 0 : revealDelays[p] ?? 0,
                                     explosionDelay: reduceMotion ? 0 : explosionDelays[p] ?? 0,
                                     reduceMotion: reduceMotion)
                            .equatable()
                            .frame(width: cell, height: cell)
                            .accessibilityElement()
                            .accessibilityLabel("Row \(r + 1), column \(c + 1)")
                            .accessibilityValue(accessibilityValue(p))
                            .accessibilityIdentifier("cell.\(r).\(c)")
                            .accessibilityAction { model.tap(p) }
                            .accessibilityActions { actions(p) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Minefield, \(state.rows) rows by \(state.cols) columns")
    }

    @ViewBuilder private func actions(_ p: GridPoint) -> some View {
        let c = state[p]
        if !state.status.isOver {
            if c.mark == .hidden {
                Button("Reveal") { model.reveal(p) }
            }
            if !c.isRevealed {
                Button(c.isFlagged ? "Remove flag" : "Flag") { model.toggleFlag(p) }
            }
            if state.canChord(at: p) {
                Button("Reveal neighbors") { model.chord(p) }
            }
        }
    }

    private func accessibilityValue(_ p: GridPoint) -> String {
        let c = state[p]
        let over = state.status.isOver
        switch c.mark {
        case .flagged:
            return over && !c.isMine && state.status == .lost ? "Flagged, not a mine" : "Flagged"
        case .revealed:
            if c.isMine { return "Mine, exploded" }
            return c.adjacent == 0 ? "Empty" : (c.adjacent == 1 ? "1 mine nearby" : "\(c.adjacent) mines nearby")
        case .hidden:
            return over && c.isMine ? "Mine" : "Hidden"
        }
    }
}

// MARK: - Hint

/// Rings the squares a hint is about (solid, pulsing) and the numbers it reasons from (soft).
private struct HintHighlight: View {
    let hint: MinesweeperModel.HintPreview
    let cell: CGFloat
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        let inset = max(1, cell * 0.05)
        let radius = cell * 0.2
        ZStack(alignment: .topLeading) {
            ForEach(Array(hint.clues), id: \.self) { p in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(HintCard.amber.opacity(0.16))
                    .strokeBorder(HintCard.amber.opacity(0.7), style: StrokeStyle(lineWidth: max(1.5, cell * 0.05), dash: [cell * 0.12, cell * 0.08]))
                    .padding(inset)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell)
            }
            ForEach(Array(hint.targets), id: \.self) { p in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(HintCard.amber.opacity(pulse ? 0.38 : 0.22))
                    .strokeBorder(HintCard.amber, lineWidth: max(2, cell * 0.08))
                    .padding(inset)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Cell

private struct MineCellView: View, Equatable {
    let cell: Minesweeper.Cell
    let status: Minesweeper.Status
    let isExploded: Bool
    let size: CGFloat
    let revealDelay: Double
    let explosionDelay: Double
    let reduceMotion: Bool

    var body: some View {
        let inset = max(1, size * 0.05)
        let radius = size * 0.2
        let lost = status == .lost
        let showMine = lost && cell.isMine && cell.mark == .hidden
        let open = cell.isRevealed || showMine

        ZStack {
            // Flat, revealed floor.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(isExploded ? MinePalette.exploded : MinePalette.open)
            // Raised, unrevealed cap that lifts away when revealed.
            RaisedTile(radius: radius, bevel: max(1, size * 0.07))
                .opacity(open ? 0 : 1)
                .scaleEffect(open && !reduceMotion ? 0.82 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16).delay(showMine ? explosionDelay : revealDelay),
                           value: open)

            content(showMine: showMine)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: cell.isFlagged)
        }
        .padding(inset)
    }

    @ViewBuilder private func content(showMine: Bool) -> some View {
        if cell.isRevealed && !cell.isMine && cell.adjacent > 0 {
            Text("\(cell.adjacent)")
                .font(.system(size: size * 0.56, weight: .heavy, design: .rounded))
                .foregroundStyle(MinePalette.number(cell.adjacent))
                .minimumScaleFactor(0.5)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16).delay(revealDelay), value: cell.isRevealed)
        } else if isExploded {
            MineGlyph(color: .white)
                .padding(size * 0.16)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else if cell.isFlagged {
            ZStack {
                FlagGlyph(size: size)
                    .opacity(status == .lost && !cell.isMine ? 0.45 : 1)
                if status == .lost && !cell.isMine {
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.62, weight: .bold))
                        .foregroundStyle(MinePalette.wrong)
                }
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
        } else if showMine {
            ExplodingMine(size: size, delay: explosionDelay, reduceMotion: reduceMotion)
        }
    }
}

/// A mine that pops in with a brief flash ring, after `delay`.
private struct ExplodingMine: View {
    let size: CGFloat
    let delay: Double
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(MinePalette.exploded.opacity(shown ? 0 : 0.8), lineWidth: size * 0.08)
                .scaleEffect(shown ? 1.15 : 0.2)
            MineGlyph(color: MinePalette.mine)
                .padding(size * 0.18)
                .scaleEffect(shown ? 1 : 0.2)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            if reduceMotion { shown = true; return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55).delay(delay)) { shown = true }
        }
    }
}

private struct RaisedTile: View {
    let radius: CGFloat
    let bevel: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [MinePalette.capTop, MinePalette.capBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [MinePalette.highlight, .clear, MinePalette.edge],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: bevel)
            }
    }
}

struct FlagGlyph: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(MinePalette.flag)
            .offset(x: size * 0.03)
    }
}

/// An original mine glyph: a round core with eight short spikes and a glint.
struct MineGlyph: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var spikes = Path()
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                spikes.move(to: CGPoint(x: c.x + cos(a) * s * 0.16, y: c.y + sin(a) * s * 0.16))
                spikes.addLine(to: CGPoint(x: c.x + cos(a) * s * 0.5, y: c.y + sin(a) * s * 0.5))
            }
            ctx.stroke(spikes, with: .color(color), style: StrokeStyle(lineWidth: max(1, s * 0.11), lineCap: .round))
            let r = s * 0.32
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            let g = s * 0.09
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45 - g, y: c.y - r * 0.45 - g, width: g * 2, height: g * 2)),
                     with: .color(.white.opacity(0.75)))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Original color scheme for the minefield, tuned for light and dark mode.
enum MinePalette {
    static let capTop = Color(light: Color(hex: 0xC9D4E6), dark: Color(hex: 0x465169))
    static let capBottom = Color(light: Color(hex: 0xADBAD2), dark: Color(hex: 0x363F54))
    static let highlight = Color(light: .white.opacity(0.75), dark: .white.opacity(0.18))
    static let edge = Color(light: Color(hex: 0x7F8DA8).opacity(0.55), dark: .black.opacity(0.35))
    static let open = Color(light: Color(hex: 0xF5F7FB), dark: Color(hex: 0x181B24))
    static let exploded = Color(hex: 0xE5484D)
    static let accent = Color(light: Color(hex: 0x4A5A78), dark: Color(hex: 0x6F84AC))
    static let win = Color(light: Color(hex: 0x1FA463), dark: Color(hex: 0x34C77F))
    static let mine = Color(light: Color(hex: 0x2A2F3D), dark: Color(hex: 0xE4E7EF))
    static let flag = Color(light: Color(hex: 0xF0483E), dark: Color(hex: 0xFF6A55))
    static let wrong = Color(light: Color(hex: 0xC2252B), dark: Color(hex: 0xFF8A80))

    private static let numbers: [Color] = [
        Color(light: Color(hex: 0x2F6FED), dark: Color(hex: 0x6EA2FF)),  // 1 blue
        Color(light: Color(hex: 0x1E9A5F), dark: Color(hex: 0x4FD394)),  // 2 green
        Color(light: Color(hex: 0xE0453F), dark: Color(hex: 0xFF7369)),  // 3 coral
        Color(light: Color(hex: 0x6A4BD1), dark: Color(hex: 0xAC93FF)),  // 4 violet
        Color(light: Color(hex: 0xB86A12), dark: Color(hex: 0xF5AE4E)),  // 5 amber
        Color(light: Color(hex: 0x0D8E9C), dark: Color(hex: 0x45D3DE)),  // 6 teal
        Color(light: Color(hex: 0xC93A8E), dark: Color(hex: 0xF57FC4)),  // 7 magenta
        Color(light: Color(hex: 0x5C6474), dark: Color(hex: 0xAEB5C3)),  // 8 slate
    ]

    static func number(_ n: Int) -> Color { numbers[max(0, min(numbers.count - 1, n - 1))] }
}
