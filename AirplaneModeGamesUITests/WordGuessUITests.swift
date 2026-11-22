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
