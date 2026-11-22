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

    @MainActor func testAutoCompleteWins() {
        let app = launch(["-solitaireScenario", "autocomplete"])
        let auto = app.buttons["autoComplete"]
        XCTAssertTrue(auto.waitForExistence(timeout: 10))
        auto.tap()
        XCTAssertTrue(app.staticTexts["You Won!"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Play Again"].exists)
    }
}
