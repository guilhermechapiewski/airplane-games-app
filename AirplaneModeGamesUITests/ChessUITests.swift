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

    func testDragAndDropMove() {
        let app = launch()
        startGame(app, mode: "passAndPlay")
        let g1 = square(app, "g1")
        XCTAssertTrue(g1.waitForExistence(timeout: 5))
        g1.press(forDuration: 0.2, thenDragTo: square(app, "f3"))
        XCTAssertTrue(moveList(app).staticTexts["Nf3"].waitForExistence(timeout: 3))
        XCTAssertEqual(square(app, "f3").label, "f3, white knight")
    }

    func testHintSuggestsAMoveForWhoeverIsToMove() {
        let app = launch()
        startGame(app, mode: "passAndPlay")
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        hint.tap()

        let banner = app.descendants(matching: .any)["hintBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "a suggestion appears within about a second")
        XCTAssertTrue(banner.label.hasPrefix("Hint: "), banner.label)
        // The suggested piece's square is marked for VoiceOver.
        let marked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'square.' AND value CONTAINS 'hint: move this piece'"))
        XCTAssertEqual(marked.count, 1)
        XCTAssertTrue(marked.firstMatch.label.contains("white"), "White is to move")

        // Closing it clears the highlight; Black can then ask after White moves.
        app.buttons["hintClose"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
        square(app, "e2").tap()
        square(app, "e4").tap()
        XCTAssertTrue(moveList(app).staticTexts["e4"].waitForExistence(timeout: 3))
        hint.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(marked.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(marked.firstMatch.label.contains("black"), "Black is to move")
    }

    func testHintFindsMateInOne() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "chess", "-chessMode", "passAndPlay",
                               "-chessMoves", "f2f3 e7e5 g2g4"]
        app.launch()
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        hint.tap()
        let banner = app.descendants(matching: .any)["hintBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Hint: queen from d8 to h4. Checkmate!")
        XCTAssertEqual(square(app, "h4").value as? String, "hint: move here")
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
