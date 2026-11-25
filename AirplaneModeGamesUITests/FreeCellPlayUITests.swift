import XCTest

/// Plays FreeCell through the UI the way a person would (following hints with drags and taps,
/// undoing now and then) and checks after every move that every card is still on the table,
/// once, lined up in its column. Columns that grow past the dealt rows once lost cards.
@MainActor
final class FreeCellPlayUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A short stretch of deal 1 that builds columns past their dealt length.
    func testCardsStayOnTheTableWhilePlaying() { play(deal: 1, steps: 24) }


    private func log(_ text: String) { XCTContext.runActivity(named: text) { _ in } }

    private struct Card { let id: String; let label: String; let value: String; let frame: CGRect }

    private func cards(_ app: XCUIApplication) -> [Card] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [Card] = []
        func walk(_ s: XCUIElementSnapshot) {
            if s.identifier.hasPrefix("card.") {
                out.append(Card(id: s.identifier, label: s.label, value: (s.value as? String) ?? "", frame: s.frame))
            }
            s.children.forEach(walk)
        }
        walk(snap)
        return out
    }

    /// Every column lists cards 1…n exactly once, stacked straight down, and no card shows twice.
    private func checkTable(_ app: XCUIApplication, _ step: Int) {
        if problems(app, step).isEmpty { return }
        let first = problems(app, step)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; shot.name = "problem-\(step)"; add(shot)
        Thread.sleep(forTimeInterval: 2)
        let later = problems(app, step)
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.lifetime = .keepAlways; shot2.name = "problem-later-\(step)"; add(shot2)
        XCTFail("first: \(first)\nafter 2s: \(later.isEmpty ? "fixed itself" : later.joined(separator: " | "))")
    }

    private func problems(_ app: XCUIApplication, _ step: Int) -> [String] {
        var issues: [String] = []
        func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ m: String) { if a != b { issues.append("\(m): \(a) vs \(b)") } }
        func XCTAssertTrue(_ a: Bool, _ m: String) { if !a { issues.append(m) } }
        func XCTAssertLessThan(_ a: CGFloat, _ b: CGFloat, _ m: String) { if !(a < b) { issues.append(m) } }
        func XCTAssertLessThanOrEqual(_ a: Int, _ b: Int, _ m: String) { if !(a <= b) { issues.append(m) } }
        let all = cards(app)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "step \(step): a card appears twice")
        var columns: [Int: [(index: Int, count: Int, card: Card)]] = [:]
        for card in all {
            let parts = card.value.replacingOccurrences(of: ", hint", with: "")
                .components(separatedBy: CharacterSet(charactersIn: " ,")).filter { !$0.isEmpty }
            // "Column 3, card 2 of 5"
            guard parts.first == "Column", parts.count >= 6, let c = Int(parts[1]), let i = Int(parts[3]),
                  let n = Int(parts[5]) else { continue }
            columns[c, default: []].append((i, n, card))
        }
        var tableauCount = 0
        for (c, list) in columns {
            let n = list[0].count
            tableauCount += n
            XCTAssertEqual(list.map(\.index).sorted(), Array(1...n), "step \(step): column \(c) indices broken; cards: \(list.map { "\($0.card.label)@\($0.index) y=\(Int($0.card.frame.minY))" }); cells/foundation: \(all.filter { !$0.value.hasPrefix("Column") }.map { "\($0.label)=\($0.value)" })")
            XCTAssertTrue(list.allSatisfy { $0.count == n }, "step \(step): column \(c) counts disagree")
            let xs = list.map(\.card.frame.midX)
            XCTAssertLessThan((xs.max() ?? 0) - (xs.min() ?? 0), 0.6,
                              "step \(step): column \(c) is not lined up: \(list.map { "\($0.card.label) x=\($0.card.frame.midX)" })")
            let ys = list.sorted { $0.index < $1.index }.map(\.card.frame.minY)
            XCTAssertEqual(ys, ys.sorted(), "step \(step): column \(c) is out of order")
        }
        let cells = all.filter { $0.value.hasPrefix("Free cell") }.count
        XCTAssertLessThanOrEqual(cells, 4, "step \(step): too many cards in free cells")
        XCTAssertLessThanOrEqual(tableauCount + cells, 52, "step \(step): too many cards")
        return issues
    }

    private func movesCount(_ app: XCUIApplication) -> Int {
        Int(app.descendants(matching: .any)["movesCount"].label.filter(\.isNumber)) ?? -1
    }

    private func play(deal: Int, steps: Int) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "freeCell", "-freeCellDeal", "\(deal)"]
        app.launch()
        let hint = app.buttons["Hint"]
        let undo = app.buttons["Undo"]
        let won = app.staticTexts["You Won!"]
        let stuck = app.staticTexts["No Moves Left"]
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: hint)], timeout: 30) == .completed)
        checkTable(app, 0)

        for step in 1...steps {
            if won.exists { break }
            XCTAssertFalse(stuck.exists, "deal \(deal): No Moves Left at step \(step)")
            if app.buttons["autoComplete"].exists, app.buttons["autoComplete"].isHittable {
                app.buttons["autoComplete"].tap()
                _ = won.waitForExistence(timeout: 30)
                break
            }
            let before = movesCount(app)
            // Every 11th step: undo the last move, then carry on.
            if step % 11 == 0, undo.isEnabled {
                undo.tap()
                Thread.sleep(forTimeInterval: 0.4)
                checkTable(app, step)
                continue
            }
            hint.tap()
            // Read the hinted run and its target from one snapshot: the hint fades after a few seconds.
            var run: [Card] = []
            var target: CGRect?
            let hintDeadline = Date().addingTimeInterval(60)
            while Date() < hintDeadline {
                if won.exists { break }
                guard let snap = try? app.snapshot() else { continue }
                var found: [Card] = []
                var ring: CGRect?
                func walk(_ s: XCUIElementSnapshot) {
                    if s.identifier.hasPrefix("card."), let v = s.value as? String, v.hasSuffix(", hint") {
                        found.append(Card(id: s.identifier, label: s.label, value: v, frame: s.frame))
                    }
                    if s.identifier == "hintTarget" { ring = s.frame }
                    s.children.forEach(walk)
                }
                walk(snap)
                if !found.isEmpty, let ring { run = found.sorted { $0.frame.minY < $1.frame.minY }; target = ring; break }
                let msg = app.descendants(matching: .any)["freeCellMessage"]
                if msg.exists {
                    // A dead end (smart taps can lead off the winning line): back up like a player would.
                    log("deal \(deal) step \(step): \(msg.label) – undoing")
                    for _ in 0..<6 where undo.isEnabled { undo.tap() }
                    Thread.sleep(forTimeInterval: 2.5)
                    hint.tap()
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            if won.exists { break }
            guard let target, let lead = run.first else {
                XCTFail("deal \(deal) step \(step): no hint within 60s"); return
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            if step % 5 == 0 {
                // Smart tap: may pick a different spot than the hint.
                origin.withOffset(CGVector(dx: lead.frame.midX, dy: lead.frame.minY + 12)).tap()
            } else {
                let from = origin.withOffset(CGVector(dx: lead.frame.midX, dy: lead.frame.minY + 12))
                let to = origin.withOffset(CGVector(dx: target.midX, dy: target.midY))
                from.press(forDuration: 0.1, thenDragTo: to)
            }
            // The move lands (moves go up, or the game ends).
            let deadline = Date().addingTimeInterval(5)
            while movesCount(app) == before && !won.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if !won.exists {
                XCTAssertNotEqual(movesCount(app), before, "deal \(deal) step \(step): the move didn't happen (\(lead.label), \(lead.value))")
            }
            Thread.sleep(forTimeInterval: 0.35) // let auto-moves and animations settle
            checkTable(app, step)
        }
    }
}
