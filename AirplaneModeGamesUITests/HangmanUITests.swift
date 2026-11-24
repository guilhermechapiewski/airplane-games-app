import XCTest

@MainActor
final class HangmanUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "hangman"]
        app.launch()
        return app
    }

    func testGuessLetterDisablesKey() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["phrase"].waitForExistence(timeout: 5))
        let key = app.buttons["key.e"]
        XCTAssertTrue(key.isEnabled)
        key.tap()
        XCTAssertFalse(key.isEnabled)
        XCTAssertFalse((key.value as? String ?? "").isEmpty, "a guessed key reports whether it was a hit")
    }

    func testHintSuggestsALetterWithoutCostingABalloon() {
        let app = launch()
        let hint = app.buttons["hangmanHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        hint.tap()
        let card = app.descendants(matching: .any)["hintCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        let text = app.staticTexts["hintExplanation"].label
        XCTAssertTrue(text.contains("still fit") || text.contains("Only one word"), text)
        let guessButton = app.buttons["hintShowAnswer"]
        XCTAssertTrue(guessButton.label.hasPrefix("Guess "), guessButton.label)
        let letter = guessButton.label.dropFirst(6).lowercased()
        XCTAssertEqual(app.descendants(matching: .any)["lives"].label, "6 of 6 balloons left")
        XCTAssertEqual(hint.value as? String, "1 used")
        guessButton.tap()
        XCTAssertFalse(card.exists)
        XCTAssertFalse(app.buttons["key.\(letter)"].isEnabled, "the suggested letter was guessed")
    }

    func testPassAndPlaySolve() {
        let app = launch()
        XCTAssertTrue(app.buttons["gameMenu"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].tap()
        app.buttons["Pass & Play"].tap()
        let field = app.secureTextFields["secretField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("ice-cream")
        app.buttons["lockSecret"].tap()
        XCTAssertTrue(app.buttons["startGuessing"].waitForExistence(timeout: 3))
        app.buttons["startGuessing"].tap()
        // The guesser can ask for a hint: it can't see the phrase, so it uses English letter frequency.
        app.buttons["hangmanHint"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hintCard"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["hintExplanation"].label.contains("most common letter in English"))
        XCTAssertEqual(app.buttons["hintShowAnswer"].label, "Guess E")
        app.buttons["hintClose"].tap()
        for ch in "icream" { app.buttons["key.\(ch)"].tap() }
        XCTAssertTrue(app.buttons["playAgain"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["lives"].label, "6 of 6 balloons left")
    }
}
