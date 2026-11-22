import SwiftUI
import GameLogic

/// Name, turn state, captured pieces and material edge for one side.
struct ChessPlayerBar: View {
    let model: ChessModel
    let side: Chess.Side

    private var isTurn: Bool { !model.isOver && model.sideToMove == side }
    private var isComputer: Bool { model.setup.isComputer && side != model.setup.humanSide }

    private var subtitle: String {
        if let outcome = model.outcome {
            if let winner = outcome.winner { return winner == side ? "Winner" : outcome.reason }
            return outcome.reason
        }
        if isComputer {
            return model.isThinking ? "Thinking…" : model.setup.level.title
        }
        if isTurn {
            if model.position.isInCheck { return "In check!" }
            return model.setup.isComputer ? "Your move" : "To move"
        }
        return model.setup.isComputer ? model.setup.humanSide.name : "Waiting"
    }

    var body: some View {
        let captured = model.game.captured(by: side).sorted { $0.points > $1.points || ($0.points == $1.points && $0.rawValue > $1.rawValue) }
        let balance = model.game.materialBalance * (side == .white ? 1 : -1)
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(side == .white ? Color(hex: 0xF7F1E6) : Color(hex: 0x2B2521))
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                if isComputer {
                    Image(systemName: "cpu")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(side == .white ? Color(hex: 0x2B2521) : Color(hex: 0xF7F1E6))
                } else {
                    ChessPieceView(piece: Chess.Piece(side, .king), size: 26)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name(for: side))
                        .font(.subheadline.weight(.bold))
                    if isComputer && model.isThinking {
                        ThinkingDots()
                    }
                }
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isTurn && model.position.isInCheck ? ChessTheme.check : .secondary)
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 6)

            HStack(spacing: -5) {
                ForEach(Array(captured.enumerated()), id: \.offset) { _, kind in
                    ChessPieceView(piece: Chess.Piece(side.opponent, kind), size: 19)
                }
            }
            .accessibilityHidden(true)
            if balance > 0 {
                Text("+\(balance)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTurn ? ChessTheme.accent.opacity(0.85) : .clear, lineWidth: 2)
        }
        .animation(.easeOut(duration: 0.2), value: isTurn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(captured: captured, balance: balance))
    }

    private func accessibilitySummary(captured: [Chess.PieceKind], balance: Int) -> String {
        var text = "\(model.name(for: side)), \(side.name). \(subtitle)."
        if !captured.isEmpty {
            text += " Captured: " + captured.map(\.name).joined(separator: ", ") + "."
        }
        if balance > 0 { text += " Ahead by \(balance)." }
        return text
    }
}

/// Three gently pulsing dots.
struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ChessTheme.accent)
                        .frame(width: 5, height: 5)
                        .opacity(reduceMotion ? 0.8 : 0.35 + 0.65 * max(0, sin((t * 5) - Double(i) * 0.9)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Move pairs "1. e4 e5" for the move list.
struct ChessMovePair: Identifiable {
    let id: Int
    let number: Int
    let white: String?
    let black: String?
    let whitePly: Int?
    let blackPly: Int?

    static func pairs(for game: Chess.Game) -> [ChessMovePair] {
        var result: [ChessMovePair] = []
        for (i, san) in game.sanMoves.enumerated() {
            let p = game.positions[i]
            if p.sideToMove == .white {
                result.append(ChessMovePair(id: result.count, number: p.fullmoveNumber, white: san, black: nil, whitePly: i, blackPly: nil))
            } else if let last = result.last, last.black == nil, last.white != nil {
                result[result.count - 1] = ChessMovePair(id: last.id, number: last.number, white: last.white, black: san,
                                                         whitePly: last.whitePly, blackPly: i)
            } else {
                result.append(ChessMovePair(id: result.count, number: p.fullmoveNumber, white: nil, black: san, whitePly: nil, blackPly: i))
            }
        }
        return result
    }
}

/// Horizontal move strip (compact layouts).
struct ChessMoveStrip: View {
    let model: ChessModel

    var body: some View {
        let pairs = ChessMovePair.pairs(for: model.game)
        let lastPly = model.game.moves.count - 1
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if pairs.isEmpty {
                        Text("Moves will appear here")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    }
                    ForEach(pairs) { pair in
                        HStack(spacing: 5) {
                            Text("\(pair.number).")
                                .foregroundStyle(.secondary)
                            ChessSANText(san: pair.white ?? "…", isLast: pair.whitePly == lastPly)
                            if let black = pair.black {
                                ChessSANText(san: black, isLast: pair.blackPly == lastPly)
                            }
                        }
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 6)
                        .id(pair.id)
                    }
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 34)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: model.game.moves.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(pairs.last?.id, anchor: .trailing) }
            }
            .onAppear { proxy.scrollTo(pairs.last?.id, anchor: .trailing) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moves")
        .accessibilityIdentifier("moveList")
    }
}

/// Vertical move table (wide layouts).
struct ChessMoveTable: View {
    let model: ChessModel

    var body: some View {
        let pairs = ChessMovePair.pairs(for: model.game)
        let lastPly = model.game.moves.count - 1
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if pairs.isEmpty {
                        Text("Moves will appear here")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(pairs) { pair in
                        HStack(spacing: 0) {
                            Text("\(pair.number).")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                            ChessSANText(san: pair.white ?? "…", isLast: pair.whitePly == lastPly)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ChessSANText(san: pair.black ?? "", isLast: pair.blackPly == lastPly)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(pair.id % 2 == 1 ? Theme.well.opacity(0.5) : .clear)
                        .id(pair.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: model.game.moves.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(pairs.last?.id, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(pairs.last?.id, anchor: .bottom) }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moves")
        .accessibilityIdentifier("moveList")
    }
}

struct ChessSANText: View {
    let san: String
    let isLast: Bool

    var body: some View {
        Text(san)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isLast ? ChessTheme.lastMove.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(san)
    }
}
