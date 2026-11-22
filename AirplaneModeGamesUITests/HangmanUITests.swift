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
        for ch in "icream" { app.buttons["key.\(ch)"].tap() }
        XCTAssertTrue(app.buttons["playAgain"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["lives"].label, "6 of 6 balloons left")
    }
}
