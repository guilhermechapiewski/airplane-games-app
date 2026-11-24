import XCTest

@MainActor
final class FreeCellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "freeCell"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements["freeCellTable"].waitForExistence(timeout: 10))
        return app
    }

    /// Card ids are suit × 13 + rank − 1 (spades, hearts, diamonds, clubs).
    private func card(_ app: XCUIApplication, _ id: Int) -> XCUIElement {
        app.descendants(matching: .any)["card.\(id)"]
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    private func wait(_ element: XCUIElement, _ format: String, _ message: String, timeout: TimeInterval = 10) {
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)],
                                      timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for the deal (the solver checks it first) and returns the top card of column 1.
    private func dealtTopCard(_ app: XCUIApplication) -> XCUIElement {
        wait(app.buttons["Hint"], "enabled == true", "the deal is ready", timeout: 30)
        let top = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card.' AND value == 'Column 1, card 7 of 7'")).firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        return app.descendants(matching: .any)[top.identifier]
    }

    func testDealTapMoveAndUndo() {
        let app = launch(["-freeCellDeal", "1"])
        let top = dealtTopCard(app)
        XCTAssertTrue(app.descendants(matching: .any)["dealNumber"].label.contains("#"))
        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled)
        let before = value(top)

        top.tap()
        wait(top, "value != '\(before)'", "a tapped card moves")
        wait(undo, "enabled == true", "the move can be undone")
        XCTAssertTrue(app.descendants(matching: .any)["movesCount"].label.contains("1"))
        attachScreenshot("after-tap")

        undo.tap()
        wait(top, "value == '\(before)'", "undo puts the card back")
        wait(undo, "enabled == false", "nothing left to undo")
    }

    func testHintHighlightsAMove() {
        let app = launch(["-freeCellDeal", "1"])
        _ = dealtTopCard(app)
        let hint = app.buttons["Hint"]
        hint.tap()
        wait(hint, "selected == true", "the Hint button lights up")
        let hinted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card.' AND value ENDSWITH ', hint'")).firstMatch
        XCTAssertTrue(hinted.waitForExistence(timeout: 10), "a card is marked as the hint")
        attachScreenshot("hint")
    }

    func testNearlySolvedTapWins() {
        let app = launch(["-freeCellScenario", "nearlySolved"])
        XCTAssertTrue(app.buttons["autoComplete"].waitForExistence(timeout: 20), "the scenario offers Auto-Complete")
        card(app, 8).tap()   // 9♠ goes up and Auto-Move plays the rest
        XCTAssertTrue(app.staticTexts["You Won!"].waitForExistence(timeout: 40), "the win card appears")
        XCTAssertTrue(app.buttons["Play Again"].exists)
        attachScreenshot("win")
    }

    func testAutoCompleteWins() {
        let app = launch(["-freeCellScenario", "nearlySolved"])
        let auto = app.buttons["autoComplete"]
        XCTAssertTrue(auto.waitForExistence(timeout: 20))
        auto.tap()
        XCTAssertTrue(app.staticTexts["You Won!"].waitForExistence(timeout: 40), "the win card appears")
    }

    /// Drags a card by touch onto its foundation, and with Auto-Move off nothing else follows.
    func testDragToFoundationWithAutoMoveOff() {
        let app = launch(["-freeCellScenario", "nearlySolved"])
        let toggle = app.buttons["autoMoveToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(value(toggle), "On")
        toggle.tap()
        wait(toggle, "value == 'Off'", "Auto-Move turns off")

        let nine = card(app, 8)        // 9♠
        let eight = card(app, 7)       // 8♠ on its foundation
        XCTAssertEqual(value(eight), "Foundation")
        nine.press(forDuration: 0.2, thenDragTo: eight)
        wait(nine, "value == 'Foundation'", "the 9 lands on its foundation", timeout: 20)
        XCTAssertTrue(value(card(app, 21)).hasPrefix("Column"), "9♥ stays put without Auto-Move")
        XCTAssertFalse(app.staticTexts["You Won!"].exists)

        // An illegal drop springs back: 9♥ can't go on the 8♦ foundation.
        let nineHearts = card(app, 21)
        let before = nineHearts.frame
        nineHearts.press(forDuration: 0.05, thenDragTo: card(app, 33))
        wait(nineHearts, "value BEGINSWITH 'Column'", "the card returns to its column")
        XCTAssertEqual(nineHearts.frame, before)
        toggle.tap()
    }

    func testRulesHaveTips() {
        let app = launch(["-freeCellScenario", "nearlySolved"])
        let menu = app.buttons["gameMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 10))
        let tips = app.staticTexts["Tips"]
        var swipes = 0
        while !tips.exists && swipes < 5 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(tips.exists)
    }

    func testNewGameMenuOffersDeals() {
        let app = launch(["-freeCellScenario", "nearlySolved"])
        let menu = app.buttons["gameMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        app.buttons["New Game"].firstMatch.tap()
        XCTAssertTrue(app.buttons["New Deal"].waitForExistence(timeout: 10), "the New Game submenu")
        XCTAssertTrue(app.buttons["Restart This Deal"].exists)
        XCTAssertTrue(app.buttons["Choose Deal Number…"].exists)
        app.buttons["Choose Deal Number…"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the deal number prompt")
        field.typeText("777")
        app.alerts.buttons["Deal"].tap()
        wait(app.buttons["Hint"], "enabled == true", "the chosen deal is dealt", timeout: 30)
        XCTAssertTrue(app.descendants(matching: .any)["dealNumber"].label.contains("#7"), "deal #777 (or the next winnable one)")
    }
}
