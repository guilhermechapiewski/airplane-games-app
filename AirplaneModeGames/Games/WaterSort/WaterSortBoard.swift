import SwiftUI
import GameLogic

/// Where each tube sits: one to three centered rows, as large as the space allows.
struct TubeLayout {
    let metrics: TubeMetrics
    /// Center of each tube's resting frame.
    let centers: [CGPoint]
    let rowGap: CGFloat

    /// Room kept above each row for a picked-up tube.
    static let liftRatio: CGFloat = 0.5

    init(count: Int, in size: CGSize, maxWidth: CGFloat) {
        let n = max(1, count)
        var best: (rows: Int, width: CGFloat) = (1, 0)
        for rows in 1...min(3, n) {
            let perRow = Int((Double(n) / Double(rows)).rounded(.up))
            let byWidth = size.width / (CGFloat(perRow) * 1.55)
            let rowHeight = TubeMetrics.heightRatio + Self.liftRatio
            let byHeight = size.height / (CGFloat(rows) * rowHeight + CGFloat(rows - 1) * 0.45)
            let w = min(byWidth, byHeight, maxWidth)
            // Another row only if it buys clearly bigger tubes.
            if w > best.width * 1.35 { best = (rows, w) }
        }
        let w = max(8, best.width)
        let m = TubeMetrics(width: w)
        metrics = m
        rowGap = w * 0.45
        let rows = best.rows
        let perRow = Int((Double(n) / Double(rows)).rounded(.up))
        let rowHeight = m.height + w * Self.liftRatio
        let total = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowGap
        let top = (size.height - total) / 2
        // Spread tubes generously, but not edge to edge.
        let pitch = min(size.width / CGFloat(perRow), w * 2.1)
        var centers: [CGPoint] = []
        for row in 0..<rows {
            // Earlier rows take the extra tubes when they don't divide evenly.
            let rowCount = n / rows + (row < n % rows ? 1 : 0)
            let y = top + CGFloat(row) * (rowHeight + rowGap) + w * Self.liftRatio + m.height / 2
            let startX = size.width / 2 - pitch * CGFloat(rowCount - 1) / 2
            for i in 0..<rowCount { centers.append(CGPoint(x: startX + pitch * CGFloat(i), y: y)) }
        }
        self.centers = Array(centers.prefix(count))
    }
}

struct WaterSortBoard: View {
    let model: WaterSortModel
    let reduceMotion: Bool
    let symbols: Bool
    let onTap: (Int) -> Void
    let onPour: (Int, Int) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { proxy in
            let layout = TubeLayout(count: model.tubeCount, in: proxy.size,
                                    maxWidth: sizeClass == .regular ? 104 : 60)
            TimelineView(.animation(minimumInterval: nil, paused: model.pours.isEmpty)) { timeline in
                board(layout: layout, now: timeline.date)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level \(model.level)")
        .accessibilityIdentifier("waterSortBoard")
    }

    private func board(layout: TubeLayout, now: Date) -> some View {
        let m = layout.metrics
        return ZStack(alignment: .topLeading) {
            racks(layout: layout)
            // Tap targets and accessibility, at the tubes' resting places.
            ForEach(0..<model.tubeCount, id: \.self) { i in
                let c = layout.centers[i]
                Color.clear
                    .frame(width: max(44, m.width * 1.5), height: m.height + m.width * TubeLayout.liftRatio)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(i) }
                    .position(x: c.x, y: c.y - m.width * TubeLayout.liftRatio / 2)
                    .modifier(TubeAccessibility(model: model, index: i, onTap: onTap, onPour: onPour))
            }
            ForEach(0..<model.tubeCount, id: \.self) { i in
                tube(i, layout: layout, now: now)
            }
            ForEach(model.pours) { anim in
                stream(anim, layout: layout, now: now)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A soft shelf under each row of tubes.
    private func racks(layout: TubeLayout) -> some View {
        let m = layout.metrics
        let rows = Dictionary(grouping: layout.centers, by: { $0.y }).sorted { $0.key < $1.key }
        return ForEach(rows, id: \.key) { y, centers in
            let minX = centers.map(\.x).min() ?? 0, maxX = centers.map(\.x).max() ?? 0
            RoundedRectangle(cornerRadius: m.width * 0.12, style: .continuous)
                .fill(Theme.well)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: m.width * 0.12, style: .continuous)
                        .fill(Theme.hairline)
                        .frame(height: max(2, m.width * 0.06))
                }
                .frame(width: maxX - minX + m.width * 1.6, height: max(6, m.width * 0.2))
                .position(x: (minX + maxX) / 2, y: y + m.height / 2 + m.width * 0.06)
                .accessibilityHidden(true)
        }
    }

    // MARK: Tubes

    @ViewBuilder
    private func tube(_ i: Int, layout: TubeLayout, now: Date) -> some View {
        let m = layout.metrics
        let c = layout.centers[i]
        let flight = model.pours.first { $0.pour.from == i }.map { PourFlight($0, layout: layout, now: now) }
        let selected = model.selected == i
        TubeView(metrics: m, layers: layers(of: i, flight: flight, now: now),
                 tilt: flight?.angle ?? .zero,
                 isSelected: selected,
                 isComplete: model.state.isComplete(i) && flight == nil && !isFilling(i),
                 symbols: symbols)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: model.state.isComplete(i))
            .rotationEffect(flight?.angle ?? .zero, anchor: flight?.anchor ?? .center)
            .offset(flight?.offset ?? CGSize(width: 0, height: selected ? -m.width * 0.42 : 0))
            .animation(flight != nil || reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: selected)
            .modifier(Shake(trigger: model.shakeTokens[i] ?? 0, amount: reduceMotion ? 0 : m.width * 0.12))
            .overlay(alignment: .top) {
                if let role = hintRole(i), flight == nil {
                    HintMarker(role: role, metrics: m, reduceMotion: reduceMotion)
                }
            }
            .overlay {
                if !reduceMotion, let token = model.sparkleTokens[i] {
                    SparkleBurst(size: m.width * 2.4).id(token)
                        .offset(y: -m.height * 0.42)
                }
            }
            .position(c)
            .zIndex(flight != nil ? 100 : selected ? 50 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Whether tube `i` is the source or the target of the hinted pour.
    private func hintRole(_ i: Int) -> HintMarker.Role? {
        guard case let .pour(p)? = model.hint else { return nil }
        return p.from == i ? .from : p.to == i ? .to : nil
    }

    private func isFilling(_ i: Int) -> Bool { model.pours.contains { $0.pour.to == i } }

    /// What a tube shows right now: its state, or the liquid in flight for an animating pour.
    private func layers(of i: Int, flight: PourFlight?, now: Date) -> [(liquid: Int, amount: Double)] {
        if let flight {
            let a = flight.anim
            let moved = Double(a.pour.count) * flight.transfer
            return a.sourceBefore.dropLast(a.pour.count).map { ($0, 1.0) }
                + [(a.pour.liquid, Double(a.pour.count) - moved)]
        }
        if let anim = model.pours.first(where: { $0.pour.to == i }) {
            let moved = Double(anim.pour.count) * PourFlight.transfer(anim, now: now)
            return anim.targetBefore.map { ($0, 1.0) } + [(anim.pour.liquid, moved)]
        }
        return model.state.tubes[i].map { ($0, 1.0) }
    }

    /// The falling stream from the tilted mouth into the target.
    @ViewBuilder
    private func stream(_ anim: WaterSortModel.PourAnimation, layout: TubeLayout, now: Date) -> some View {
        let flight = PourFlight(anim, layout: layout, now: now)
        if flight.streaming {
            let m = layout.metrics
            let target = layout.centers[anim.pour.to]
            let mouth = flight.mouth
            let filled = Double(anim.targetBefore.count) + Double(anim.pour.count) * flight.transfer
            let surface = target.y + m.height / 2 - m.wall - CGFloat(filled) * m.layer
            let style = LiquidStyle.of(anim.pour.liquid)
            let length = max(0, surface - mouth.y)
            Capsule()
                .fill(LinearGradient(colors: [style.highlight, style.color], startPoint: .leading, endPoint: .trailing))
                .frame(width: m.width * 0.16, height: length)
                .position(x: mouth.x, y: mouth.y + length / 2)
                .zIndex(90)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Where the source tube of a pour is at a moment: flying over, tilting, pouring, flying back.
struct PourFlight {
    let anim: WaterSortModel.PourAnimation
    let offset: CGSize
    let angle: Angle
    let anchor: UnitPoint
    /// Share of the liquid poured so far.
    let transfer: Double
    let streaming: Bool
    /// The pouring corner, on screen.
    let mouth: CGPoint

    // Phases of the animation, as shares of its duration.
    static let moveEnd = 0.3
    static let pourEnd = 0.68

    static func progress(_ anim: WaterSortModel.PourAnimation, now: Date) -> Double {
        min(1, max(0, now.timeIntervalSince(anim.start) / WaterSortModel.PourAnimation.duration))
    }

    static func transfer(_ anim: WaterSortModel.PourAnimation, now: Date) -> Double {
        let p = progress(anim, now: now)
        return easeInOut(min(1, max(0, (p - moveEnd) / (pourEnd - moveEnd))))
    }

    init(_ anim: WaterSortModel.PourAnimation, layout: TubeLayout, now: Date) {
        self.anim = anim
        let m = layout.metrics
        let from = layout.centers[anim.pour.from], to = layout.centers[anim.pour.to]
        let p = Self.progress(anim, now: now)
        let dir: CGFloat = to.x >= from.x ? 1 : -1
        anchor = dir > 0 ? .topTrailing : .topLeading
        let rest = CGPoint(x: from.x + dir * m.width / 2, y: from.y - m.height / 2)
        let goal = CGPoint(x: to.x - dir * m.width * 0.08, y: to.y - m.height / 2 - m.width * 0.55)
        transfer = Self.transfer(anim, now: now)

        // Tilt so the surface reaches the mouth: steeper as the tube empties.
        let units = Double((m.height - m.wall) / m.layer)
        func tilt(level: Double) -> Double {
            let rise = (units - level) * Double(m.layer)
            return min(80, max(48, atan(2 * rise / Double(m.width)) * 180 / .pi))
        }
        let full = Double(anim.sourceBefore.count)
        let level = full - Double(anim.pour.count) * transfer
        let travel: Double
        let degrees: Double
        if p < Self.moveEnd {
            travel = Self.easeInOut(p / Self.moveEnd)
            degrees = tilt(level: full) * travel
        } else if p < Self.pourEnd {
            travel = 1
            degrees = tilt(level: level)
        } else {
            travel = 1 - Self.easeInOut((p - Self.pourEnd) / (1 - Self.pourEnd))
            degrees = tilt(level: level) * travel
        }
        angle = .degrees(Double(dir) * degrees)
        offset = CGSize(width: (goal.x - rest.x) * travel, height: (goal.y - rest.y) * travel)
        mouth = CGPoint(x: rest.x + offset.width, y: rest.y + offset.height)
        streaming = p > Self.moveEnd && p < Self.pourEnd + 0.04
    }

    static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
}

// MARK: - Accessibility

private struct TubeAccessibility: ViewModifier {
    let model: WaterSortModel
    let index: Int
    let onTap: (Int) -> Void
    let onPour: (Int, Int) -> Void

    func body(content: Content) -> some View {
        let state = model.state
        let selected = model.selected == index
        let targets = state.canPick(index) ? state.targets(from: index) : []
        content
            .accessibilityElement()
            .accessibilityLabel("Tube \(index + 1)")
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onTap(index) }
            .accessibilityActions {
                ForEach(targets, id: \.self) { target in
                    Button("Pour into tube \(target + 1)") { onPour(index, target) }
                }
            }
            .accessibilityIdentifier("tube.\(index + 1)")
    }

    private var value: String {
        // A tube being removed (restart after the extra tube) can update once more before it goes.
        guard model.state.tubes.indices.contains(index) else { return "" }
        let layers = model.state.tubes[index]
        if layers.isEmpty { return "empty" }
        if model.state.isComplete(index) { return "complete, \(LiquidStyle.of(layers[0]).name)" }
        let names = layers.map { LiquidStyle.of($0).name }.joined(separator: ", ")
        let count = layers.count == 1 ? "1 layer" : "\(layers.count) layers"
        return "\(count): from bottom \(names)"
    }

    private var hint: String {
        if model.selected == index { return "Picked up. Double-tap to put it back, or pick a tube to pour into." }
        if let from = model.selected {
            return model.state.canPour(from: from, to: index) ? "Double-tap to pour here." : "Can't pour here."
        }
        return model.state.canPick(index) ? "Double-tap to pick up." : ""
    }
}

// MARK: - Hint

/// An amber outline around a hinted tube, with an arrow above it: up to pick it up, down to pour in.
struct HintMarker: View {
    enum Role { case from, to }
    let role: Role
    let metrics: TubeMetrics
    let reduceMotion: Bool
    @State private var bob = false

    var body: some View {
        let m = metrics
        ZStack(alignment: .top) {
            TubeShape(lip: m.lip)
                .stroke(HintCard.amber, lineWidth: max(2, m.width * 0.07))
                .shadow(color: HintCard.amber.opacity(0.7), radius: m.width * 0.12)
                .frame(width: m.width + m.width * 0.16, height: m.height + m.width * 0.16)
                .offset(y: -m.width * 0.08)
            Image(systemName: role == .from ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: max(14, m.width * 0.5), weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, HintCard.amber)
                .offset(y: -m.width * (bob ? 0.95 : 0.8))
        }
        .frame(width: m.width, height: m.height, alignment: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bob = true }
        }
    }
}

// MARK: - Effects

private struct Shake: ViewModifier {
    let trigger: Int
    let amount: CGFloat

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-amount, duration: 0.05)
                LinearKeyframe(amount, duration: 0.08)
                LinearKeyframe(-amount * 0.6, duration: 0.07)
                LinearKeyframe(amount * 0.3, duration: 0.06)
                LinearKeyframe(0, duration: 0.05)
            }
        }
    }
}

/// A little burst of bubbles and sparkles above a tube that was just completed.
private struct SparkleBurst: View {
    let size: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let angle = Double(i) / 9 * 2 * .pi - .pi / 2
                let dist = size * (i.isMultiple(of: 2) ? 0.42 : 0.3)
                Image(systemName: i.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                    .font(.system(size: size * (i.isMultiple(of: 3) ? 0.16 : 0.07), weight: .bold))
                    .foregroundStyle(i.isMultiple(of: 3) ? Color(hex: 0xFFD45A) : Color.white.opacity(0.9))
                    .offset(x: go ? cos(angle) * dist : 0, y: go ? sin(angle) * dist : 0)
                    .scaleEffect(go ? 0.4 : 1)
                    .opacity(go ? 0 : 1)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { go = true }
        }
    }
}
