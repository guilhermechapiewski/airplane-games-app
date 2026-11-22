import XCTest

@MainActor
final class ChessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "chess"]
        app.launch()
        return app
    }

    private func startGame(_ app: XCUIApplication, mode: String) {
        let modeCard = app.buttons["setup.mode.\(mode)"]
        XCTAssertTrue(modeCard.waitForExistence(timeout: 5), "setup sheet should appear on first launch")
        modeCard.tap()
        app.buttons["setup.start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chessBoard"].waitForExistence(timeout: 5))
    }

    private func square(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["square.\(name)"]
    }

    private func moveList(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["moveList"]
    }

    func testPassAndPlayMoveAppearsInMoveList() {
        let app = launch()
        startGame(app, mode: "passAndPlay")

        let e2 = square(app, "e2")
        XCTAssertTrue(e2.waitForExistence(timeout: 5))
        XCTAssertEqual(e2.label, "e2, white pawn")
        e2.tap()
        square(app, "e4").tap()

        XCTAssertTrue(moveList(app).staticTexts["e4"].waitForExistence(timeout: 3))
        XCTAssertEqual(square(app, "e4").label, "e4, white pawn")
        XCTAssertEqual(square(app, "e2").label, "e2, empty")
        XCTAssertTrue(app.buttons["Undo"].isEnabled)

        // Black replies; then undo takes back one ply at a time.
        square(app, "e7").tap()
        square(app, "e5").tap()
        XCTAssertTrue(moveList(app).staticTexts["e5"].waitForExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertFalse(moveList(app).staticTexts["e5"].waitForExistence(timeout: 1))
        XCTAssertTrue(moveList(app).staticTexts["e4"].exists)
    }

    func testComputerReplies() {
        let app = launch()
        startGame(app, mode: "computer")
        square(app, "d2").tap()
        square(app, "d4").tap()
        XCTAssertTrue(moveList(app).staticTexts["d4"].waitForExistence(timeout: 3))
        // The computer (Black) answers on its own: "1.", "d4" and its reply.
        let replied = expectation(for: NSPredicate(format: "count >= 3"),
                                  evaluatedWith: moveList(app).staticTexts)
        wait(for: [replied], timeout: 10)
        // Undo takes back both the reply and the player's move.
        app.buttons["Undo"].tap()
        XCTAssertEqual(square(app, "d2").label, "d2, white pawn")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }
}
