import XCTest

@MainActor
final class WordGuessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "wordGuess"]
        app.launch()
        return app
    }

    private func typeOnScreen(_ word: String, in app: XCUIApplication) {
        for ch in word {
            app.buttons["key.\(ch)"].tap()
        }
    }

    func testTypeAndSubmitGuessWithOnScreenKeyboard() {
        let app = launch()
        XCTAssertTrue(app.buttons["key.q"].waitForExistence(timeout: 5))
        typeOnScreen("cranx", in: app)
        app.buttons["key.delete"].tap()
        typeOnScreen("e", in: app)
        app.buttons["key.enter"].tap()
        let row = app.descendants(matching: .any)["row0"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("CRANE"), "row label was \(row.label)")
        // An invalid word is rejected and stays in the next row.
        typeOnScreen("zzzzz", in: app)
        app.buttons["key.enter"].tap()
        let next = app.descendants(matching: .any)["row1"]
        XCTAssertTrue(next.label.contains("typing"), "row label was \(next.label)")
    }

    func testHintSuggestsAGuessAndTypesIt() {
        let app = launch()
        let hint = app.buttons["wordGuessHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        // Before the first guess: a strong opener.
        hint.tap()
        let card = app.descendants(matching: .any)["hintCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let explanation = app.staticTexts["hintExplanation"]
        XCTAssertTrue(explanation.label.contains("strong first guess"), explanation.label)
        let typeButton = app.buttons["hintShowAnswer"]
        XCTAssertTrue(typeButton.label.hasPrefix("Type "), typeButton.label)
        let suggested = String(typeButton.label.dropFirst(5))
        typeButton.tap()
        XCTAssertFalse(card.exists)
        let row0 = app.descendants(matching: .any)["row0"]
        XCTAssertTrue(row0.label.contains(suggested.map(String.init).joined(separator: " ")), row0.label)
        XCTAssertEqual(hint.value as? String, "1 used")

        // Asking again before guessing shows the same hint without counting another.
        hint.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["hintClose"].tap()
        XCTAssertEqual(hint.value as? String, "1 used")

        // After a guess the hint explains how many words still fit.
        app.buttons["key.enter"].tap()
        let row1 = app.descendants(matching: .any)["row1"]
        XCTAssertTrue(row0.waitForLabel(containing: suggested, timeout: 3))
        sleep(2)   // let the tiles flip
        guard row1.label.contains("empty") else { return }   // the opener was the answer
        hint.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let text = explanation.label
        XCTAssertTrue(text.contains("still fit") || text.contains("Every clue points"), text)
        XCTAssertEqual(hint.value as? String, "2 used")
    }

    /// Leaving right after the winning guess (while its tiles still flip) must still count the win.
    func testWinCountsWhenLeavingDuringTheReveal() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "wordGuess", "-demoState"]   // answer CRANE, "CR" typed
        app.launch()
        XCTAssertTrue(app.buttons["key.a"].waitForExistence(timeout: 5))
        typeOnScreen("ane", in: app)
        app.buttons["key.enter"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        sleep(2)   // longer than the reveal

        let card = app.buttons["game.wordGuess"]
        var attempts = 0
        while !card.isHittable && attempts < 6 { app.swipeUp(velocity: .slow); attempts += 1 }
        card.tap()
        XCTAssertTrue(app.buttons["gameMenu"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["Statistics"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["1, Won"].waitForExistence(timeout: 3))
    }

    func testPassAndPlayRound() {
        let app = launch()
        XCTAssertTrue(app.buttons["gameMenu"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].tap()
        app.buttons["Pass & Play"].tap()
        XCTAssertTrue(app.buttons["startMatch"].waitForExistence(timeout: 3))
        app.buttons["startMatch"].tap()

        let field = app.secureTextFields["secretField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("plane")
        app.buttons["lockSecret"].tap()
        XCTAssertTrue(app.buttons["startGuessing"].waitForExistence(timeout: 3))
        app.buttons["startGuessing"].tap()

        typeOnScreen("plane", in: app)
        app.buttons["key.enter"].tap()
        XCTAssertTrue(app.buttons["nextRound"].waitForExistence(timeout: 6))
        app.buttons["nextRound"].tap()
        XCTAssertTrue(app.secureTextFields["secretField"].waitForExistence(timeout: 3))
    }
}

private extension XCUIElement {
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
