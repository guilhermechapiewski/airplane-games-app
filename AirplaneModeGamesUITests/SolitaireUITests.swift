import XCTest

final class SolitaireUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "solitaire"] + args
        app.launch()
        return app
    }

    @MainActor private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let enabled = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }

    @MainActor func testDrawUndoAndMenu() {
        let app = launch()
        let stock = app.descendants(matching: .any)["stock"].firstMatch
        XCTAssertTrue(stock.waitForExistence(timeout: 10))
        // The deal is ready once the stock accepts taps.
        waitUntilEnabled(stock)

        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled)
        stock.tap()
        waitUntilEnabled(undo, timeout: 3)
        undo.tap()
        let disabled = expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: undo)
        wait(for: [disabled], timeout: 3)

        // Menu: New Game submenu offers both draw modes.
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Draw 3"].waitForExistence(timeout: 3))
        app.buttons["Draw 3"].tap()
        XCTAssertTrue(app.staticTexts["Mode: Draw 3"].waitForExistence(timeout: 5))

        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
    }

    /// Drags a tableau card onto its foundation by touch (not the accessibility action), and
    /// checks that an illegal drop springs the card back to where it was.
    @MainActor func testDragCardToFoundation() {
        let app = launch(["-solitaireScenario", "autocomplete"])
        XCTAssertTrue(app.buttons["autoComplete"].waitForExistence(timeout: 10))
        let ranks = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card.'"))
        let foundations = cards.matching(NSPredicate(format: "value == 'Foundation'")).allElementsBoundByIndex
        XCTAssertFalse(foundations.isEmpty)

        // Illegal drop: a column card released over empty table space returns to its column.
        let anyColumnCard = cards.matching(NSPredicate(format: "value BEGINSWITH 'Column'")).firstMatch
        let before = anyColumnCard.frame
        anyColumnCard.press(forDuration: 0.05, thenDragTo: app.buttons["autoComplete"])
        let returned = expectation(for: NSPredicate(format: "frame == %@", NSValue(cgRect: before)), evaluatedWith: anyColumnCard)
        wait(for: [returned], timeout: 3)

        // Legal drop: find a column card that is the next card for some foundation.
        for foundation in foundations {
            let parts = foundation.label.components(separatedBy: " of ")
            guard parts.count == 2, let rank = ranks.firstIndex(of: parts[0]), rank + 1 < ranks.count else { continue }
            let match = cards.matching(NSPredicate(format: "label == %@ AND value BEGINSWITH 'Column'",
                                                   "\(ranks[rank + 1]) of \(parts[1])")).firstMatch
            guard match.exists else { continue }
            // Pin by identifier: once it lands, the card no longer matches the "Column" query.
            let next = cards[match.identifier]
            next.press(forDuration: 0.05, thenDragTo: foundation)
            let landed = expectation(for: NSPredicate(format: "value == 'Foundation'"), evaluatedWith: next)
            if XCTWaiter().wait(for: [landed], timeout: 3) == .completed { return }
        }
        XCTFail("no column card could be dragged onto a foundation")
    }

    @MainActor func testAutoCompleteWins() {
        let app = launch(["-solitaireScenario", "autocomplete"])
        let auto = app.buttons["autoComplete"]
        XCTAssertTrue(auto.waitForExistence(timeout: 10))
        auto.tap()
        XCTAssertTrue(app.staticTexts["You Won!"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Play Again"].exists)
    }
}
