import SwiftUI
import GameLogic

/// Geometry of the table: card size, pile positions and tableau fanning.
struct TableLayout {
    let size: CGSize
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let gap: CGFloat
    let originX: CGFloat
    let tableauTop: CGFloat

    init(size: CGSize) {
        self.size = size
        let gap = min(14, max(5, (size.width * 0.014).rounded()))
        let byWidth = (size.width - gap * 6) / 7
        // Leave room for the top row plus a reasonably fanned tableau.
        let byHeight = size.height / (SolitaireMetrics.aspect * 4.2)
        let width = max(24, floor(min(byWidth, byHeight, 124)))
        self.gap = gap
        cardWidth = width
        cardHeight = (width * SolitaireMetrics.aspect).rounded()
        originX = ((size.width - (width * 7 + gap * 6)) / 2).rounded()
        tableauTop = cardHeight + max(12, gap * 2.2)
    }

    var boardWidth: CGFloat { cardWidth * 7 + gap * 6 }
    var wasteFanStep: CGFloat { cardWidth * 0.3 }

    func x(_ column: Int) -> CGFloat { originX + cardWidth / 2 + CGFloat(column) * (cardWidth + gap) }
    var topY: CGFloat { cardHeight / 2 }
    var stockCenter: CGPoint { CGPoint(x: x(0), y: topY) }
    var wasteCenter: CGPoint { CGPoint(x: x(1), y: topY) }
    func foundationCenter(_ f: Int) -> CGPoint { CGPoint(x: x(3 + f), y: topY) }

    /// Vertical spacing for face-down and face-up cards, compressed if the column is too tall.
    func fan(for column: Solitaire.Column) -> (down: CGFloat, up: CGFloat) {
        var down = max(5, cardHeight * 0.11)
        var up = cardHeight * 0.29
        let available = size.height - tableauTop - cardHeight - 4
        let natural = CGFloat(column.faceDownCount) * down + CGFloat(max(0, column.faceUpCount - 1)) * up
        if natural > available, natural > 0 {
            let scale = max(0.2, available / natural)
            down *= scale
            up *= scale
        }
        return (down, up)
    }

    func tableauCenter(column c: Int, index: Int, in column: Solitaire.Column) -> CGPoint {
        let fan = fan(for: column)
        let downs = min(index, column.faceDownCount)
        let ups = max(0, index - column.faceDownCount)
        let y = tableauTop + cardHeight / 2 + CGFloat(downs) * fan.down + CGFloat(ups) * fan.up
        return CGPoint(x: x(c), y: y)
    }

    func frame(center: CGPoint) -> CGRect {
        CGRect(x: center.x - cardWidth / 2, y: center.y - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    /// Area that accepts a drop onto tableau column `c`.
    func dropZone(column c: Int, in column: Solitaire.Column) -> CGRect {
        let bottom = column.isEmpty ? tableauTop + cardHeight
            : tableauCenter(column: c, index: column.cards.count - 1, in: column).y + cardHeight / 2
        return CGRect(x: x(c) - cardWidth / 2 - gap / 2, y: tableauTop - gap,
                      width: cardWidth + gap, height: max(bottom, tableauTop + cardHeight) - tableauTop + gap + cardHeight * 0.5)
    }

    func dropZone(foundation f: Int) -> CGRect {
        frame(center: foundationCenter(f)).insetBy(dx: -gap / 2, dy: -gap)
    }
}

/// Where and how a card is drawn.
private struct Placement {
    var center: CGPoint
    var faceUp: Bool
    var z: Double
    var pile: Solitaire.Pile
    var index: Int
    /// The card is exposed to VoiceOver.
    var accessible: Bool
    var order: Int
}

private struct DragState {
    var lead: Solitaire.Card
    var ids: [Int]
    var translation: CGSize = .zero
}

struct SolitaireTable: View {
    let model: SolitaireModel
    let showsCascade: Bool

    @State private var drag: DragState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let space = "solitaireTable"

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size)
            let placements = placements(layout)
            ZStack(alignment: .topLeading) {
                slots(layout)
                if !showsCascade {
                    ForEach(Solitaire.Card.deck) { card in
                        if let p = placements[card.id] {
                            cardView(card, p, layout)
                        }
                    }
                }
                stockButton(layout)
                hintTarget(layout)
                if showsCascade {
                    WinCascade(foundations: model.state.foundations,
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
        .accessibilityIdentifier("solitaireTable")
    }

    // MARK: Placement

    private func placements(_ layout: TableLayout) -> [Int: Placement] {
        let s = model.state
        var result: [Int: Placement] = [:]
        let dealing = model.phase == .preparing || model.phase == .dealing
        for (i, card) in s.stock.enumerated() {
            let lift = CGFloat(i / 6) * 0.6
            result[card.id] = Placement(center: CGPoint(x: layout.stockCenter.x - lift, y: layout.stockCenter.y - lift),
                                        faceUp: false, z: Double(i), pile: .stock, index: i, accessible: false, order: 0)
        }
        let fanCount = min(s.wasteFan, s.waste.count)
        for (i, card) in s.waste.enumerated() {
            let fanIndex = i - (s.waste.count - fanCount)
            let dx = fanIndex > 0 ? CGFloat(fanIndex) * layout.wasteFanStep : 0
            result[card.id] = Placement(center: CGPoint(x: layout.wasteCenter.x + dx, y: layout.wasteCenter.y),
                                        faceUp: true, z: 100 + Double(i), pile: .waste, index: i,
                                        accessible: i == s.waste.count - 1, order: 1)
        }
        for (f, pile) in s.foundations.enumerated() {
            for (i, card) in pile.enumerated() {
                result[card.id] = Placement(center: layout.foundationCenter(f), faceUp: true, z: 100 + Double(i),
                                            pile: .foundation(f), index: i, accessible: i == pile.count - 1, order: 2 + f)
            }
        }
        for (c, column) in s.tableau.enumerated() {
            for (i, card) in column.cards.enumerated() {
                let order = 10 + c * 30 + i
                if dealing, Self.dealIndex(column: c, row: i) >= model.dealtCount {
                    let deal = Self.dealIndex(column: c, row: i)
                    result[card.id] = Placement(center: layout.stockCenter, faceUp: false, z: 60 + Double(28 - deal),
                                                pile: .tableau(c), index: i, accessible: false, order: order)
                } else {
                    result[card.id] = Placement(center: layout.tableauCenter(column: c, index: i, in: column),
                                                faceUp: column.isFaceUp(i), z: 100 + Double(i), pile: .tableau(c),
                                                index: i, accessible: true, order: order)
                }
            }
        }
        return result
    }

    private static func dealIndex(column: Int, row: Int) -> Int {
        SolitaireModel.dealIndex(column: column, row: row)
    }

    // MARK: Cards

    @ViewBuilder
    private func cardView(_ card: Solitaire.Card, _ p: Placement, _ layout: TableLayout) -> some View {
        let dragIndex = drag?.ids.firstIndex(of: card.id)
        let isDragged = dragIndex != nil
        let offset = isDragged ? drag?.translation ?? .zero : .zero
        let z = isDragged ? 2000 + Double(dragIndex ?? 0) : model.raisedIDs.contains(card.id) ? 1000 + p.z : p.z
        let highlighted = hintSources.contains(card.id)

        PlayingCard(card: card, faceUp: p.faceUp, width: layout.cardWidth)
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: layout.cardWidth * SolitaireMetrics.cornerRatio, style: .continuous)
                        .strokeBorder(SolitairePalette.hint, lineWidth: 2.5)
                        .shadow(color: SolitairePalette.hint.opacity(0.9), radius: 6)
                        .transition(.opacity)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(isDragged ? 0.35 : 0.22), radius: isDragged ? 10 : 0.8,
                    y: isDragged ? 8 : 0.6)
            .scaleEffect(isDragged && !reduceMotion ? 1.05 : 1)
            .modifier(ShakeEffect(trigger: model.shakeCount(card.id), enabled: !reduceMotion))
            .position(x: p.center.x + offset.width, y: p.center.y + offset.height)
            .zIndex(z)
            .allowsHitTesting(p.pile != .stock && model.isInteractive)
            .onTapGesture {
                withAnimation(SolitaireModel.cardAnimation) { model.tap(card) }
            }
            .gesture(dragGesture(for: card, layout: layout))
            .modifier(CardAccessibility(card: card, placement: p, model: model))
    }

    private var hintSources: Set<Int> {
        guard let move = model.hint else { return [] }
        let s = model.state
        switch move.from {
        case .stock: return Set(s.stock.suffix(1).map(\.id))
        case .waste: return move.to == .stock ? [] : Set(s.waste.suffix(1).map(\.id))
        case .foundation(let f): return Set(s.foundations[f].suffix(1).map(\.id))
        case .tableau(let t): return Set(s.tableau[t].cards.suffix(move.count).map(\.id))
        }
    }

    private func dragGesture(for card: Solitaire.Card, layout: TableLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    guard let lifted = model.liftedCards(for: card) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        drag = DragState(lead: lifted[0], ids: lifted.map(\.id))
                    }
                    Haptics.select()
                }
                guard drag?.ids.first == card.id || drag?.ids.contains(card.id) == true else { return }
                drag?.translation = value.translation
            }
            .onEnded { _ in finishDrag(layout) }
    }

    private func finishDrag(_ layout: TableLayout) {
        guard let current = drag else { return }
        let s = model.state
        guard let (pile, index) = s.location(of: current.lead) else { drag = nil; return }
        let count = current.ids.count
        let start = placementCenter(pile: pile, index: index, layout: layout)
        let dropped = layout.frame(center: CGPoint(x: start.x + current.translation.width,
                                                   y: start.y + current.translation.height))
        var best: (pile: Solitaire.Pile, area: CGFloat)?
        var zones: [(Solitaire.Pile, CGRect)] = (0..<7).map { (.tableau($0), layout.dropZone(column: $0, in: s.tableau[$0])) }
        if count == 1 { zones += (0..<4).map { (.foundation($0), layout.dropZone(foundation: $0)) } }
        for (target, zone) in zones where target != pile {
            let overlap = zone.intersection(dropped)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            guard area > (best?.area ?? 0), s.isLegal(Solitaire.Move(from: pile, to: target, count: count)) else { continue }
            best = (target, area)
        }
        let moved = hypot(current.translation.width, current.translation.height)
        if let best {
            withAnimation(SolitaireModel.cardAnimation) {
                drag = nil
                model.drop(current.lead, on: best.pile)
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { drag = nil }
            if moved > layout.cardWidth * 0.4 {
                model.reject(s.cards(in: pile).suffix(count))
            }
        }
    }

    private func placementCenter(pile: Solitaire.Pile, index: Int, layout: TableLayout) -> CGPoint {
        let s = model.state
        switch pile {
        case .stock: return layout.stockCenter
        case .waste:
            let fan = min(s.wasteFan, s.waste.count)
            let fanIndex = index - (s.waste.count - fan)
            return CGPoint(x: layout.wasteCenter.x + (fanIndex > 0 ? CGFloat(fanIndex) * layout.wasteFanStep : 0),
                           y: layout.wasteCenter.y)
        case .foundation(let f): return layout.foundationCenter(f)
        case .tableau(let t): return layout.tableauCenter(column: t, index: index, in: s.tableau[t])
        }
    }

    // MARK: Slots, stock & hint target

    private func slots(_ layout: TableLayout) -> some View {
        let s = model.state
        return ZStack(alignment: .topLeading) {
            PileSlot(width: layout.cardWidth,
                     symbol: s.stock.isEmpty ? (s.waste.isEmpty ? nil : "arrow.counterclockwise") : nil)
                .position(layout.stockCenter)
                .accessibilityHidden(true)
            PileSlot(width: layout.cardWidth)
                .position(layout.wasteCenter)
                .opacity(0.5)
                .accessibilityHidden(true)
            ForEach(0..<4, id: \.self) { f in
                PileSlot(width: layout.cardWidth, label: "A")
                    .position(layout.foundationCenter(f))
                    .accessibilityElement()
                    .accessibilityLabel("Empty foundation")
                    .accessibilitySortPriority(Double(1000 - 2 - f))
                    .accessibilityHidden(!s.foundations[f].isEmpty)
            }
            ForEach(0..<7, id: \.self) { c in
                PileSlot(width: layout.cardWidth, label: "K")
                    .position(x: layout.x(c), y: layout.tableauTop + layout.cardHeight / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Empty column \(c + 1)")
                    .accessibilitySortPriority(Double(1000 - 10 - c * 30))
                    .accessibilityHidden(!s.tableau[c].isEmpty)
            }
        }
        .allowsHitTesting(false)
    }

    private func stockButton(_ layout: TableLayout) -> some View {
        let s = model.state
        let value: String = if !s.stock.isEmpty {
            "\(s.stock.count) cards"
        } else if !s.waste.isEmpty {
            "Empty. Double-tap to turn the waste over."
        } else {
            "Empty"
        }
        return Color.clear
            .frame(width: layout.cardWidth + layout.gap, height: layout.cardHeight + layout.gap)
            .contentShape(Rectangle())
            .position(layout.stockCenter)
            .zIndex(2500)
            .onTapGesture {
                withAnimation(SolitaireModel.cardAnimation) { model.tapStock() }
            }
            .accessibilityElement()
            .accessibilityLabel("Stock")
            .accessibilityValue(value)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation(SolitaireModel.cardAnimation) { model.tapStock() } }
            .accessibilitySortPriority(1000)
            .accessibilityIdentifier("stock")
            .disabled(!model.isInteractive)
    }

    @ViewBuilder
    private func hintTarget(_ layout: TableLayout) -> some View {
        if let move = model.hint {
            let s = model.state
            let center: CGPoint = switch move.to {
            case .waste: layout.wasteCenter
            case .stock: layout.stockCenter
            case .foundation(let f): layout.foundationCenter(f)
            case .tableau(let t):
                s.tableau[t].isEmpty ? CGPoint(x: layout.x(t), y: layout.tableauTop + layout.cardHeight / 2)
                    : layout.tableauCenter(column: t, index: s.tableau[t].cards.count - 1, in: s.tableau[t])
            }
            // For a draw, point at the stock itself.
            let target = move.from == .stock || move.to == .stock ? layout.stockCenter : center
            HintRing(width: layout.cardWidth)
                .position(target)
                .zIndex(3000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}

// MARK: - Effects

/// A short horizontal shake for a rejected move.
private struct ShakeEffect: ViewModifier {
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
                SpringKeyframe(CGFloat(0), duration: 0.1)
            }
        }
    }
}

/// Pulsing outline marking where a hinted move goes.
private struct HintRing: View {
    let width: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: width * SolitaireMetrics.cornerRatio, style: .continuous)
            .strokeBorder(SolitairePalette.hint, lineWidth: 3)
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

private struct CardAccessibility: ViewModifier {
    let card: Solitaire.Card
    let placement: Placement
    let model: SolitaireModel

    func body(content: Content) -> some View {
        if !placement.accessible {
            content.accessibilityHidden(true)
        } else if !placement.faceUp {
            content
                .accessibilityElement()
                .accessibilityLabel("Face-down card")
                .accessibilityValue(location)
                .accessibilitySortPriority(Double(1000 - placement.order))
        } else {
            content
                .accessibilityElement()
                .accessibilityLabel(card.name)
                .accessibilityValue(location)
                .accessibilityHint("Double-tap to move it to the best place.")
                .accessibilityAddTraits(.isButton)
                .accessibilitySortPriority(Double(1000 - placement.order))
                .accessibilityIdentifier("card.\(card.id)")
                .accessibilityAction { withAnimation(SolitaireModel.cardAnimation) { model.tap(card) } }
                .accessibilityActions {
                    ForEach(model.legalMoves(for: card), id: \.self) { move in
                        Button(actionName(move)) {
                            withAnimation(SolitaireModel.cardAnimation) { _ = model.perform(move) }
                        }
                    }
                }
        }
    }

    private var location: String {
        switch placement.pile {
        case .stock: "Stock"
        case .waste: "Waste"
        case .foundation: "Foundation"
        case .tableau(let t): "Column \(t + 1)"
        }
    }

    private func actionName(_ move: Solitaire.Move) -> String {
        let what = move.count > 1 ? "Move \(move.count) cards" : "Move"
        switch move.to {
        case .foundation: return "\(what) to foundation"
        case .tableau(let t):
            return model.state.tableau[t].top.map { "\(what) onto \($0.name), column \(t + 1)" }
                ?? "\(what) to empty column \(t + 1)"
        case .stock, .waste: return what
        }
    }
}
