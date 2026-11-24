import SwiftUI
import GameLogic

/// Geometry of the FreeCell table: a top row of four free cells and four foundations over
/// eight columns.
struct FreeCellLayout {
    let size: CGSize
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let gap: CGFloat
    let originX: CGFloat
    let tableauTop: CGFloat

    init(size: CGSize) {
        self.size = size
        let gap = min(14, max(4, (size.width * 0.012).rounded()))
        let byWidth = (size.width - gap * 7) / 8
        // Leave room for the top row plus a well fanned tableau.
        let byHeight = size.height / (SolitaireMetrics.aspect * 4.6)
        let width = max(24, floor(min(byWidth, byHeight, 124)))
        self.gap = gap
        cardWidth = width
        cardHeight = (width * SolitaireMetrics.aspect).rounded()
        originX = ((size.width - (width * 8 + gap * 7)) / 2).rounded()
        tableauTop = cardHeight + max(12, gap * 2.2)
    }

    func x(_ column: Int) -> CGFloat { originX + cardWidth / 2 + CGFloat(column) * (cardWidth + gap) }
    var topY: CGFloat { cardHeight / 2 }
    func cellCenter(_ c: Int) -> CGPoint { CGPoint(x: x(c), y: topY) }
    func foundationCenter(_ f: Int) -> CGPoint { CGPoint(x: x(4 + f), y: topY) }
    /// Where undealt cards wait: just below the table's bottom edge, in the middle.
    var deckPoint: CGPoint { CGPoint(x: size.width / 2, y: size.height + cardHeight) }

    /// Vertical spacing between cards of a column, compressed if the column is too tall.
    func fan(count: Int) -> CGFloat {
        let available = size.height - tableauTop - cardHeight - 4
        // Use the table's height: fan wide enough that a 13-card column just fits, within limits.
        let up = min(cardHeight * 0.42, max(cardHeight * 0.29, available / 12))
        let natural = CGFloat(max(0, count - 1)) * up
        guard natural > available, natural > 0 else { return up }
        return up * max(0.2, available / natural)
    }

    func tableauCenter(column c: Int, index: Int, count: Int) -> CGPoint {
        CGPoint(x: x(c), y: tableauTop + cardHeight / 2 + CGFloat(index) * fan(count: count))
    }

    func emptyColumnCenter(_ c: Int) -> CGPoint { CGPoint(x: x(c), y: tableauTop + cardHeight / 2) }

    func frame(center: CGPoint) -> CGRect {
        CGRect(x: center.x - cardWidth / 2, y: center.y - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    /// Area that accepts a drop onto tableau column `c` holding `count` cards.
    func dropZone(column c: Int, count: Int) -> CGRect {
        let bottom = count == 0 ? tableauTop + cardHeight
            : tableauCenter(column: c, index: count - 1, count: count).y + cardHeight / 2
        return CGRect(x: x(c) - cardWidth / 2 - gap / 2, y: tableauTop - gap,
                      width: cardWidth + gap, height: max(bottom, tableauTop + cardHeight) - tableauTop + gap + cardHeight * 0.5)
    }

    func dropZone(center: CGPoint) -> CGRect {
        frame(center: center).insetBy(dx: -gap / 2, dy: -gap / 2)
    }
}

/// Where and how a card is drawn.
private struct Placement {
    var center: CGPoint
    var z: Double
    var pile: FreeCell.Pile
    var index: Int
    /// Cards in the same pile (for the spoken position).
    var pileCount: Int
    var dealt: Bool
    /// Exposed to VoiceOver.
    var accessible: Bool
    var order: Int
}

private struct DragState {
    var lead: FreeCell.Card
    var ids: [Int]
}

/// The finger's offset during a drag, kept apart so per-frame updates only re-render the dragged cards.
@Observable @MainActor
private final class FreeCellDragOffset {
    var translation: CGSize = .zero
}

private struct FreeCellDragFollow: ViewModifier {
    let offset: FreeCellDragOffset
    let active: Bool

    func body(content: Content) -> some View {
        content.offset(active ? offset.translation : .zero)
    }
}

struct FreeCellTable: View {
    let model: FreeCellModel
    let showsCascade: Bool

    @State private var drag: DragState?
    @State private var dragOffset = FreeCellDragOffset()
    /// Resets when the system cancels a drag, which `onEnded` never hears about.
    @GestureState private var isDragging = false
    @Environment(\.reduceMotion) private var reduceMotion
    @Environment(\.differentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.scenePhase) private var scenePhase
    private static let space = "freeCellTable"

    var body: some View {
        GeometryReader { geo in
            let layout = FreeCellLayout(size: geo.size)
            let placements = placements(layout)
            ZStack(alignment: .topLeading) {
                slots(layout)
                if !showsCascade {
                    ForEach(FreeCell.Card.deck) { card in
                        if let p = placements[card.id] {
                            cardView(card, p, layout)
                        }
                    }
                }
                hintTarget(layout)
                if showsCascade {
                    WinCascade(foundations: (0..<4).map { model.state.foundationCards($0) },
                               centers: (0..<4).map(layout.foundationCenter),
                               cardWidth: layout.cardWidth, start: model.celebrationStart) {
                        model.finishCelebration()
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("freeCellTable")
        .onGestureCancelled(isDragging) { cancelDrag() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelDrag() }
        }
    }

    private func cancelDrag() {
        guard drag != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            drag = nil
            dragOffset.translation = .zero
        }
    }

    // MARK: Placement

    private func placements(_ layout: FreeCellLayout) -> [Int: Placement] {
        let s = model.state
        var result: [Int: Placement] = [:]
        for (c, card) in s.cells.enumerated() {
            guard let card else { continue }
            result[card.id] = Placement(center: layout.cellCenter(c), z: 100, pile: .cell(c), index: 0, pileCount: 1,
                                        dealt: true, accessible: true, order: c)
        }
        for f in 0..<4 {
            let cards = s.foundationCards(f)
            for (i, card) in cards.enumerated() {
                result[card.id] = Placement(center: layout.foundationCenter(f), z: 100 + Double(i), pile: .foundation(f),
                                            index: i, pileCount: cards.count, dealt: true,
                                            accessible: i == cards.count - 1, order: 4 + f)
            }
        }
        for (c, column) in s.tableau.enumerated() {
            for (i, card) in column.enumerated() {
                let deal = FreeCellModel.dealIndex(column: c, row: i)
                let dealt = deal < model.dealtCount
                result[card.id] = Placement(
                    center: dealt ? layout.tableauCenter(column: c, index: i, count: column.count) : layout.deckPoint,
                    z: dealt ? 100 + Double(i) : 60 - Double(deal) / 10, pile: .tableau(c), index: i,
                    pileCount: column.count, dealt: dealt, accessible: dealt, order: 10 + c * 40 + i)
            }
        }
        return result
    }

    // MARK: Cards

    @ViewBuilder
    private func cardView(_ card: FreeCell.Card, _ p: Placement, _ layout: FreeCellLayout) -> some View {
        let dragIndex = drag?.ids.firstIndex(of: card.id)
        let isDragged = dragIndex != nil
        let z = isDragged ? 2000 + Double(dragIndex ?? 0) : model.raisedIDs.contains(card.id) ? 1000 + p.z : p.z
        let highlighted = hintSources.contains(card.id)

        PlayingCard(card: card, faceUp: true, width: layout.cardWidth)
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: layout.cardWidth * SolitaireMetrics.cornerRatio, style: .continuous)
                        .strokeBorder(SolitairePalette.hint, lineWidth: 2.5)
                        .shadow(color: SolitairePalette.hint.opacity(0.9), radius: 6)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if highlighted && differentiateWithoutColor && hintSources.first == card.id {
                    // Not just a colored glow: a lightbulb badge marks the card to move.
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: max(9, layout.cardWidth * 0.2), weight: .bold))
                        .foregroundStyle(.black)
                        .padding(3)
                        .background(SolitairePalette.hint, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(isDragged ? 0.35 : 0.22), radius: isDragged ? 10 : 0.8,
                    y: isDragged ? 8 : 0.6)
            .scaleEffect(isDragged && !reduceMotion ? 1.05 : 1)
            .animation(.easeOut(duration: 0.12), value: isDragged)
            .modifier(FreeCellShake(trigger: model.shakeCount(card.id), enabled: !reduceMotion))
            .position(p.center)
            .modifier(FreeCellDragFollow(offset: dragOffset, active: isDragged))
            .opacity(p.dealt ? 1 : 0)
            .zIndex(z)
            .allowsHitTesting(p.dealt && p.pile != .foundation(card.suit.rawValue) && model.isInteractive)
            .onTapGesture {
                withAnimation(FreeCellModel.cardAnimation) { model.tap(card) }
            }
            .gesture(dragGesture(for: card, layout: layout))
            .modifier(FreeCellCardAccessibility(card: card, placement: p, model: model, hinted: highlighted))
    }

    private var hintSources: [Int] {
        guard let move = model.hint else { return [] }
        return model.state.cards(in: move.from).suffix(move.count).map(\.id)
    }

    private func dragGesture(for card: FreeCell.Card, layout: FreeCellLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .tracking($isDragging)
            .onChanged { value in
                if drag == nil {
                    guard let lifted = model.liftedCards(for: card) else { return }
                    dragOffset.translation = value.translation
                    drag = DragState(lead: lifted[0], ids: lifted.map(\.id))
                    Haptics.select()
                }
                guard drag?.ids.contains(card.id) == true else { return }
                dragOffset.translation = value.translation
            }
            .onEnded { _ in finishDrag(layout) }
    }

    private func finishDrag(_ layout: FreeCellLayout) {
        guard let current = drag else { return }
        let translation = dragOffset.translation
        let s = model.state
        guard let (pile, index) = s.location(of: current.lead) else {
            drag = nil
            dragOffset.translation = .zero
            return
        }
        let count = current.ids.count
        let start = center(pile: pile, index: index, layout: layout)
        let dropped = layout.frame(center: CGPoint(x: start.x + translation.width, y: start.y + translation.height))
        var zones: [(FreeCell.Pile, CGRect)] = (0..<8).map { (.tableau($0), layout.dropZone(column: $0, count: s.tableau[$0].count)) }
        if count == 1 {
            zones += (0..<4).map { (.cell($0), layout.dropZone(center: layout.cellCenter($0))) }
            zones += (0..<4).map { (.foundation($0), layout.dropZone(center: layout.foundationCenter($0))) }
        }
        var best: (pile: FreeCell.Pile, area: CGFloat)?
        var blockedByLimit = false
        for (target, zone) in zones where target != pile {
            let overlap = zone.intersection(dropped)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            guard area > (best?.area ?? 0) else { continue }
            if s.isLegal(FreeCell.Move(from: pile, to: target, count: count)) {
                best = (target, area)
            } else if case .tableau(let t) = target, count > 1,
                      count > s.maxMovable(toEmptyColumn: s.tableau[t].isEmpty) {
                blockedByLimit = true
            }
        }
        let moved = hypot(translation.width, translation.height)
        if let best {
            withAnimation(FreeCellModel.cardAnimation) {
                drag = nil
                dragOffset.translation = .zero
                model.drop(current.lead, on: best.pile)
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                drag = nil
                dragOffset.translation = .zero
            }
            if moved > layout.cardWidth * 0.4 {
                model.reject(s.cards(in: pile).suffix(count))
                if blockedByLimit {
                    let limit = s.maxMovable(toEmptyColumn: false)
                    model.show("With these free cells and columns, you can move \(limit) \(limit == 1 ? "card" : "cards") at once.")
                }
            }
        }
    }

    private func center(pile: FreeCell.Pile, index: Int, layout: FreeCellLayout) -> CGPoint {
        switch pile {
        case .cell(let c): layout.cellCenter(c)
        case .foundation(let f): layout.foundationCenter(f)
        case .tableau(let t): layout.tableauCenter(column: t, index: index, count: model.state.tableau[t].count)
        }
    }

    // MARK: Slots & hint target

    private func slots(_ layout: FreeCellLayout) -> some View {
        let s = model.state
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { c in
                FreeCellSlot(width: layout.cardWidth, kind: .cell)
                    .position(layout.cellCenter(c))
                    .accessibilityElement()
                    .accessibilityLabel("Free cell \(c + 1)")
                    .accessibilityValue("Empty")
                    .accessibilitySortPriority(Double(1000 - c))
                    .accessibilityHidden(s.cells[c] != nil)
            }
            ForEach(0..<4, id: \.self) { f in
                let suit = FreeCell.Suit(rawValue: f)!
                FreeCellSlot(width: layout.cardWidth, kind: .foundation(suit))
                    .position(layout.foundationCenter(f))
                    .accessibilityElement()
                    .accessibilityLabel("\(suit.name) foundation")
                    .accessibilityValue("Empty")
                    .accessibilitySortPriority(Double(1000 - 4 - f))
                    .accessibilityHidden(s.foundations[f] > 0)
            }
            ForEach(0..<8, id: \.self) { c in
                FreeCellSlot(width: layout.cardWidth, kind: .column)
                    .position(layout.emptyColumnCenter(c))
                    .accessibilityElement()
                    .accessibilityLabel("Column \(c + 1)")
                    .accessibilityValue("Empty")
                    .accessibilitySortPriority(Double(1000 - 10 - c * 40))
                    .accessibilityHidden(!s.tableau[c].isEmpty || model.phase == .preparing)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hintTarget(_ layout: FreeCellLayout) -> some View {
        if let move = model.hint {
            let s = model.state
            let center: CGPoint = switch move.to {
            case .cell(let c): layout.cellCenter(c)
            case .foundation(let f): layout.foundationCenter(f)
            case .tableau(let t):
                s.tableau[t].isEmpty ? layout.emptyColumnCenter(t)
                    : layout.tableauCenter(column: t, index: s.tableau[t].count - 1, count: s.tableau[t].count)
            }
            FreeCellHintRing(width: layout.cardWidth)
                .position(center)
                .zIndex(3000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}

// MARK: - Slots & effects

/// An empty free cell, foundation (showing its suit) or column.
private struct FreeCellSlot: View {
    enum Kind: Equatable {
        case cell
        case foundation(FreeCell.Suit)
        case column
    }

    let width: CGFloat
    let kind: Kind

    var body: some View {
        let radius = width * SolitaireMetrics.cornerRatio
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.black.opacity(kind == .cell ? 0.2 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SolitairePalette.slot,
                                  style: StrokeStyle(lineWidth: 1.5, dash: kind == .cell ? [] : [5, 4]))
            }
            .overlay {
                switch kind {
                case .foundation(let suit):
                    Image(systemName: suit.symbolName)
                        .font(.system(size: width * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                case .cell:
                    Image(systemName: "tray")
                        .font(.system(size: width * 0.3, weight: .regular))
                        .foregroundStyle(.white.opacity(0.18))
                case .column:
                    EmptyView()
                }
            }
            .frame(width: width, height: width * SolitaireMetrics.aspect)
            .dynamicTypeSize(.large)
    }
}

/// A short horizontal shake for a rejected move.
private struct FreeCellShake: ViewModifier {
    let trigger: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
            view.offset(x: enabled ? x : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(CGFloat(-7), duration: 0.05)
                LinearKeyframe(CGFloat(6), duration: 0.07)
                LinearKeyframe(CGFloat(-4), duration: 0.07)
                LinearKeyframe(CGFloat(2), duration: 0.06)
                // Must end exactly at rest: the animator keeps its last keyframe's value.
                CubicKeyframe(CGFloat(0), duration: 0.1)
            }
        }
    }
}

/// Pulsing outline marking where a hinted move goes.
private struct FreeCellHintRing: View {
    let width: CGFloat
    @State private var pulse = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: width * SolitaireMetrics.cornerRatio, style: .continuous)
            .strokeBorder(SolitairePalette.hint, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
            .shadow(color: SolitairePalette.hint, radius: pulse ? 10 : 3)
            .frame(width: width, height: width * SolitaireMetrics.aspect)
            .scaleEffect(pulse ? 1.06 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - Accessibility

private struct FreeCellCardAccessibility: ViewModifier {
    let card: FreeCell.Card
    let placement: Placement
    let model: FreeCellModel
    let hinted: Bool

    func body(content: Content) -> some View {
        if !placement.accessible {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityElement()
                .accessibilityLabel(card.name)
                .accessibilityValue(hinted ? "\(location), hint" : location)
                .accessibilityHint(isFoundation ? "" : "Double-tap to move it to the best place.")
                .accessibilityAddTraits(isFoundation ? [] : .isButton)
                .accessibilitySortPriority(Double(1000 - placement.order))
                .accessibilityIdentifier("card.\(card.id)")
                .accessibilityAction { withAnimation(FreeCellModel.cardAnimation) { model.tap(card) } }
                .accessibilityActions {
                    ForEach(model.legalMoves(for: card), id: \.self) { move in
                        Button(actionName(move)) {
                            withAnimation(FreeCellModel.cardAnimation) { _ = model.perform(move) }
                        }
                    }
                }
        }
    }

    private var isFoundation: Bool {
        if case .foundation = placement.pile { true } else { false }
    }

    private var location: String {
        switch placement.pile {
        case .cell(let c): "Free cell \(c + 1)"
        case .foundation: "Foundation"
        case .tableau(let t): "Column \(t + 1), card \(placement.index + 1) of \(placement.pileCount)"
        }
    }

    private func actionName(_ move: FreeCell.Move) -> String {
        let what = move.count > 1 ? "Move \(move.count) cards" : "Move"
        switch move.to {
        case .foundation: return "\(what) to foundation"
        case .cell: return "\(what) to a free cell"
        case .tableau(let t):
            return model.state.tableau[t].last.map { "\(what) onto \($0.name), column \(t + 1)" }
                ?? "\(what) to empty column \(t + 1)"
        }
    }
}
