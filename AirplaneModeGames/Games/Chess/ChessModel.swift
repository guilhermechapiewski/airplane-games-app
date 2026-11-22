import SwiftUI
import GameLogic

/// How a chess game is being played.
struct ChessSetup: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case computer, passAndPlay
        var id: String { rawValue }
        var title: String { self == .computer ? "vs. Computer" : "Pass & Play" }
    }

    enum ColorChoice: String, Codable, CaseIterable, Identifiable {
        case white, black, random
        var id: String { rawValue }
        var title: String {
            switch self {
            case .white: "White"
            case .black: "Black"
            case .random: "Random"
            }
        }
    }

    var mode: Mode = .computer
    var colorChoice: ColorChoice = .white
    var level: Chess.Level = .casual
    /// The human's side in a computer game (resolved from `colorChoice`).
    var humanSide: Chess.Side = .white

    var isComputer: Bool { mode == .computer }

    func resolved() -> ChessSetup {
        var s = self
        switch colorChoice {
        case .white: s.humanSide = .white
        case .black: s.humanSide = .black
        case .random: s.humanSide = Bool.random() ? .white : .black
        }
        return s
    }
}

/// A piece on screen with a stable identity so moves animate.
struct ChessToken: Identifiable, Equatable {
    let id: Int
    var piece: Chess.Piece
    var square: Chess.Square
}

/// Win/loss/draw tally per computer level (the shared stats only track wins).
struct ChessRecord: Codable, Equatable {
    var wins = 0, losses = 0, draws = 0
    var total: Int { wins + losses + draws }
}

@MainActor @Observable
final class ChessModel {
    typealias Side = Chess.Side
    typealias Square = Chess.Square

    private struct Saved: Codable {
        var game: Chess.Game
        var setup: ChessSetup
        var clock: GameClock
    }

    private(set) var game: Chess.Game
    private(set) var setup: ChessSetup
    private(set) var tokens: [ChessToken] = []
    private(set) var selected: Square?
    private(set) var targets: [Chess.Move] = []
    /// A pawn move awaiting the promotion choice.
    private(set) var pendingPromotion: (from: Square, to: Square)?
    private(set) var isThinking = false
    private(set) var outcome: Chess.Outcome?
    var showResult = false
    var showSetup = false
    /// Bumped on every board change; drives the check pulse and VoiceOver announcements.
    private(set) var changeCount = 0
    private(set) var records: [String: ChessRecord]
    var autoRotate: Bool {
        didSet {
            UserDefaults.standard.set(autoRotate, forKey: Self.autoRotateKey)
            syncOrientation()
        }
    }
    /// Which side is drawn at the bottom of the board. In pass & play it follows the
    /// side to move shortly after each move (when auto-rotate is on).
    private(set) var bottomSide: Side = .white

    private var clock = GameClock()
    private var aiTask: Task<Void, Never>?
    private var generation = 0
    private var nextTokenID = 0
    private var isActive = false
    private let store: GameStore
    private let stats: StatsStore
    let gameID = GameID.chess

    private static let autoRotateKey = "chess.autoRotate"
    private static let lastSetupKey = "chess.lastSetup"
    private static let recordsKey = "chess.records"

    init(store: GameStore = .shared, stats: StatsStore = .shared) {
        self.store = store
        self.stats = stats
        autoRotate = UserDefaults.standard.object(forKey: Self.autoRotateKey) as? Bool ?? true
        records = store.load([String: ChessRecord].self, key: Self.recordsKey) ?? [:]
        if let saved = store.load(Saved.self, key: GameID.chess.saveKey), saved.game.outcome == nil {
            game = saved.game
            setup = saved.setup
            clock = saved.clock
        } else {
            game = Chess.Game()
            setup = Self.lastSetup.resolved()
            showSetup = true
        }
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
        syncTokens()
        bottomSide = targetBottomSide
    }

    private var orientationTask: Task<Void, Never>?

    /// Updates the board orientation, optionally after a pause so the last move can be seen.
    private func syncOrientation(delayed: Bool = false) {
        orientationTask?.cancel()
        let target = targetBottomSide
        guard target != bottomSide else { return }
        guard delayed else {
            bottomSide = target
            return
        }
        orientationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, !Task.isCancelled, !self.isOver else { return }
            self.bottomSide = self.targetBottomSide
        }
    }

    #if DEBUG
    /// `-chessMoves "e2e4 e7e5"` and `-chessMode passAndPlay|computer` set up a game for screenshots.
    private func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let mode = value("-chessMode").flatMap(ChessSetup.Mode.init(rawValue:)) {
            setup.mode = mode
            showSetup = false
        }
        if let side = value("-chessSide") { setup.humanSide = side == "black" ? .black : .white }
        if let moves = value("-chessMoves") {
            game = Chess.Game()
            for uci in moves.split(separator: " ") { game.play(uci: String(uci)) }
            outcome = game.outcome
            showResult = outcome != nil
            showSetup = false
        }
    }
    #endif

    static var lastSetup: ChessSetup {
        guard let data = UserDefaults.standard.data(forKey: lastSetupKey),
              let s = try? JSONDecoder().decode(ChessSetup.self, from: data) else { return ChessSetup() }
        return s
    }

    // MARK: Derived state

    var position: Chess.Position { game.position }
    var sideToMove: Side { game.sideToMove }
    var isOver: Bool { outcome != nil }

    private var targetBottomSide: Side {
        switch setup.mode {
        case .computer: setup.humanSide
        case .passAndPlay: autoRotate ? sideToMove : .white
        }
    }

    var isHumanTurn: Bool {
        !isOver && (!setup.isComputer || sideToMove == setup.humanSide)
    }

    var checkedKing: Square? {
        position.isInCheck ? position.kingSquare(sideToMove) : nil
    }

    var canUndo: Bool {
        guard !isOver else { return false }
        if setup.isComputer {
            // Need at least one human move on the record.
            return game.moves.indices.contains { game.positions[$0].sideToMove == setup.humanSide }
        }
        return !game.moves.isEmpty
    }

    var canResign: Bool { !isOver && !game.moves.isEmpty }

    func name(for side: Side) -> String {
        guard setup.isComputer else { return side.name }
        return side == setup.humanSide ? "You" : "Computer"
    }

    func record(for level: Chess.Level) -> ChessRecord { records["level\(level.rawValue)"] ?? ChessRecord() }

    var statusText: String {
        if let outcome { return outcomeTitle(outcome) }
        if isThinking { return "Thinking…" }
        let check = position.isInCheck
        if setup.isComputer {
            return sideToMove == setup.humanSide ? (check ? "Check! Your move" : "Your move") : "Computer to move"
        }
        return "\(sideToMove.name) to move" + (check ? " — check!" : "")
    }

    func outcomeTitle(_ outcome: Chess.Outcome) -> String {
        guard let winner = outcome.winner else { return "Draw" }
        if setup.isComputer { return winner == setup.humanSide ? "You Won!" : "You Lost" }
        return "\(winner.name) Wins"
    }

    /// nil = draw; true = a win worth celebrating (any decisive pass & play result).
    var resultIsWin: Bool? {
        guard let winner = outcome?.winner else { return nil }
        return setup.isComputer ? winner == setup.humanSide : true
    }

    // MARK: Input

    func tap(_ square: Square) {
        guard isHumanTurn, pendingPromotion == nil else { return }
        if let selected, targets.contains(where: { $0.to == square }) {
            attemptMove(from: selected, to: square)
            return
        }
        if let piece = position.piece(at: square), piece.side == sideToMove {
            if selected == square {
                clearSelection()
            } else {
                select(square)
            }
            return
        }
        if selected != nil {
            clearSelection()
            Feedback.play(.tap)
        }
    }

    func select(_ square: Square) {
        guard isHumanTurn, let piece = position.piece(at: square), piece.side == sideToMove else { return }
        selected = square
        targets = position.legalMoves(from: square)
        Feedback.play(.select)
    }

    func clearSelection() {
        selected = nil
        targets = []
    }

    func canDrag(from square: Square) -> Bool {
        isHumanTurn && pendingPromotion == nil && position.piece(at: square)?.side == sideToMove
    }

    /// Returns true if a move (or a promotion prompt) resulted.
    @discardableResult
    func attemptMove(from: Square, to: Square) -> Bool {
        guard isHumanTurn else { return false }
        let candidates = position.legalMoves(from: from).filter { $0.to == to }
        guard let first = candidates.first else {
            if from != to { Feedback.play(.invalid) }
            return false
        }
        if candidates.count > 1 {
            pendingPromotion = (from, to)
            selected = from
            targets = []
            return true
        }
        play(first)
        return true
    }

    func promote(to kind: Chess.PieceKind) {
        guard let pending = pendingPromotion,
              let move = position.legalMove(from: pending.from, to: pending.to, promotion: kind) else { return }
        pendingPromotion = nil
        play(move)
    }

    func cancelPromotion() {
        pendingPromotion = nil
        clearSelection()
    }

    // MARK: Moves

    private func play(_ move: Chess.Move, byComputer: Bool = false) {
        let before = position
        guard game.play(move) else { return }
        clearSelection()
        pendingPromotion = nil
        generation += 1
        changeCount += 1
        clock.start()
        syncTokens()
        syncOrientation(delayed: true)

        let after = position
        if after.isInCheck {
            Feedback.play(.pop)
        } else if move.isCapture {
            Feedback.play(.eat)
        } else {
            Feedback.play(.place)
        }
        if byComputer {
            announce("Computer played " + Self.spokenDescription(of: move, in: before, after: after))
        }

        outcome = game.outcome
        if let outcome {
            finish(outcome)
        } else {
            scheduleComputerIfNeeded()
        }
        persist()
    }

    private func scheduleComputerIfNeeded() {
        guard setup.isComputer, !isOver, sideToMove != setup.humanSide, isActive else { return }
        aiTask?.cancel()
        isThinking = true
        let snapshot = game
        let level = setup.level
        let token = generation
        aiTask = Task { [weak self] in
            let start = ContinuousClock.now
            let search = Task.detached(priority: .userInitiated) {
                Chess.Engine.chooseMove(for: snapshot, level: level)
            }
            let move = await withTaskCancellationHandler {
                await search.value
            } onCancel: {
                search.cancel()
            }
            // A short pause so instant replies don't feel abrupt.
            let minimum = ContinuousClock.now - start < .milliseconds(450)
            if minimum { try? await Task.sleep(until: start + .milliseconds(450), clock: .continuous) }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.isThinking = false
            guard let move else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                self.play(move, byComputer: true)
            }
        }
    }

    private func cancelComputer() {
        aiTask?.cancel()
        aiTask = nil
        isThinking = false
        generation += 1
    }

    func undo() {
        guard canUndo else { return }
        cancelComputer()
        if setup.isComputer {
            // Take back the computer's reply (if any) and the player's last move.
            while let last = game.positions.dropLast().last, last.sideToMove != setup.humanSide {
                game.undo()
            }
            game.undo()
        } else {
            game.undo()
        }
        outcome = nil
        clearSelection()
        pendingPromotion = nil
        changeCount += 1
        syncTokens()
        syncOrientation()
        Feedback.play(.flip)
        persist()
    }

    func resign() {
        guard canResign else { return }
        cancelComputer()
        let side = setup.isComputer ? setup.humanSide : sideToMove
        game.resign(side)
        clearSelection()
        pendingPromotion = nil
        outcome = game.outcome
        if let outcome { finish(outcome) }
        persist()
    }

    func newGame(_ newSetup: ChessSetup) {
        cancelComputer()
        let resolved = newSetup.resolved()
        if let data = try? JSONEncoder().encode(newSetup) {
            UserDefaults.standard.set(data, forKey: Self.lastSetupKey)
        }
        setup = resolved
        game = Chess.Game()
        outcome = nil
        showResult = false
        clearSelection()
        pendingPromotion = nil
        clock = GameClock()
        changeCount += 1
        store.remove(key: gameID.saveKey)
        syncTokens()
        syncOrientation()
        Feedback.play(.flip)
        scheduleComputerIfNeeded()
    }

    /// Same settings again (colour re-drawn when random).
    func rematch() {
        newGame(setup)
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            if !isOver && !game.moves.isEmpty { clock.start() }
            if !isThinking { scheduleComputerIfNeeded() }
        } else {
            clock.pause()
            cancelComputer()
            persist()
        }
    }

    private func finish(_ outcome: Chess.Outcome) {
        clock.pause()
        isThinking = false
        let time = clock.elapsed()
        if setup.isComputer {
            let key = "level\(setup.level.rawValue)"
            let won = outcome.winner == setup.humanSide
            stats.record(gameID, variant: key, won: won, time: time)
            var r = records[key] ?? ChessRecord()
            if outcome.isDraw { r.draws += 1 } else if won { r.wins += 1 } else { r.losses += 1 }
            records[key] = r
            store.save(records, key: Self.recordsKey)
            Feedback.play(outcome.isDraw ? .clear : (won ? .win : .lose))
        } else {
            stats.record(gameID, variant: "passAndPlay", won: !outcome.isDraw, time: time)
            Feedback.play(outcome.isDraw ? .clear : .win)
        }
        announce(outcomeTitle(outcome) + ". " + outcome.reason)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, self.outcome == outcome else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.showResult = true }
        }
    }

    private func persist() {
        if isOver || game.moves.isEmpty {
            store.remove(key: gameID.saveKey)
        } else {
            store.save(Saved(game: game, setup: setup, clock: clock), key: gameID.saveKey)
        }
    }

    // MARK: Tokens

    /// Matches on-screen tokens to the current position so pieces slide instead of reappearing.
    private func syncTokens() {
        let placed = position.pieces
        var remaining = tokens
        var result: [ChessToken] = []
        var unplaced: [(square: Square, piece: Chess.Piece)] = []

        for entry in placed {
            if let i = remaining.firstIndex(where: { $0.square == entry.square && $0.piece == entry.piece }) {
                result.append(remaining.remove(at: i))
            } else {
                unplaced.append(entry)
            }
        }
        func distance(_ a: Square, _ b: Square) -> Int { abs(a.file - b.file) + abs(a.rank - b.rank) }
        // Same piece moved; then same side changed kind (promotion or its undo).
        for pass in 0..<2 {
            unplaced = unplaced.filter { entry in
                let candidates = remaining.indices.filter {
                    pass == 0 ? remaining[$0].piece == entry.piece : remaining[$0].piece.side == entry.piece.side
                }
                guard let i = candidates.min(by: { distance(remaining[$0].square, entry.square) < distance(remaining[$1].square, entry.square) }) else {
                    return true
                }
                var token = remaining.remove(at: i)
                token.square = entry.square
                token.piece = entry.piece
                result.append(token)
                return false
            }
        }
        for entry in unplaced {
            result.append(ChessToken(id: nextTokenID, piece: entry.piece, square: entry.square))
            nextTokenID += 1
        }
        tokens = result.sorted { $0.id < $1.id }
    }

    // MARK: Accessibility

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    static func spokenDescription(of move: Chess.Move, in before: Chess.Position, after: Chess.Position) -> String {
        guard let piece = before.piece(at: move.from) else { return move.uci }
        var text: String
        if move.isCastle {
            text = move.to.file == 6 ? "castles kingside" : "castles queenside"
        } else {
            text = "\(piece.kind.name) \(move.from.name) "
            if move.isCapture {
                let victim = move.isEnPassant ? "pawn" : before.piece(at: move.to)?.kind.name ?? "piece"
                text += "takes \(victim) on \(move.to.name)"
                if move.isEnPassant { text += " en passant" }
            } else {
                text += "to \(move.to.name)"
            }
            if let promo = move.promotion { text += ", promotes to \(promo.name)" }
        }
        if after.isInCheck { text += after.hasLegalMove ? ", check" : ", checkmate" }
        return text
    }
}
