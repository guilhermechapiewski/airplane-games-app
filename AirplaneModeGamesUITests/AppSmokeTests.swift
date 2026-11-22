import XCTest

@MainActor
final class AppSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    func testHomeListsGamesAndOpensSettings() {
        let app = launch()
        XCTAssertTrue(app.buttons["game.twentyFortyEight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["game.sudoku"].exists)
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["aboutLink"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["reportBugLink"].waitForExistence(timeout: 3))
        app.navigationBars["About"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
    }

    func testEveryGameOpensFromHome() {
        let app = launch()
        let ids = ["twentyFortyEight", "sudoku", "solitaire", "blocks", "tileMatch", "minesweeper",
                   "chess", "wordGuess", "nonograms", "wordSearch", "snake", "hangman"]
        for id in ids {
            let card = app.buttons["game.\(id)"]
            var attempts = 0
            while !card.isHittable && attempts < 6 { app.swipeUp(velocity: .slow); attempts += 1 }
            card.tap()
            // A tap that lands while the scroll view is still decelerating only stops the scroll.
            if !app.buttons["gameMenu"].waitForExistence(timeout: 2) { card.tap() }
            XCTAssertTrue(app.buttons["gameMenu"].waitForExistence(timeout: 5), "\(id) did not open")
            // Some games (e.g. Chess) greet first-time players with a setup sheet.
            let cancel = app.buttons["Cancel"]
            if cancel.waitForExistence(timeout: 1) { cancel.tap() }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        }
    }

    func test2048SwipesAndMenu() {
        let app = launch(["-openGame", "twentyFortyEight"])
        let board = app.otherElements["board2048"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            board.swipeLeft(); board.swipeUp(); board.swipeRight(); board.swipeDown()
        }
        // Undo becomes available after at least one effective move.
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
    }

    /// Swipes that start off the board (including at the left screen edge) move the tiles and
    /// never pop back to the home screen.
    func test2048SwipesAnywhereWithoutGoingBack() {
        let app = launch(["-openGame", "twentyFortyEight"])
        XCTAssertTrue(app.otherElements["board2048"].waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        func swipe(from: CGVector, to: CGVector) {
            window.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.01, thenDragTo: window.coordinate(withNormalizedOffset: to))
        }
        for _ in 0..<3 {
            swipe(from: CGVector(dx: 0.01, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))    // right, from the edge
            swipe(from: CGVector(dx: 0.02, dy: 0.75), to: CGVector(dx: 0.02, dy: 0.35)) // up, beside the board
            swipe(from: CGVector(dx: 0.98, dy: 0.5), to: CGVector(dx: 0.3, dy: 0.5))    // left
            swipe(from: CGVector(dx: 0.98, dy: 0.35), to: CGVector(dx: 0.98, dy: 0.75)) // down
        }
        XCTAssertTrue(app.buttons["gameMenu"].exists, "a swipe went back to the home screen")
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "off-board swipes moved the tiles")
    }

    /// "Continue Playing" resumes; a game's card starts over, after confirming when a game is in progress.
    func testCardStartsNewGameAfterConfirmingAndChipResumes() {
        let app = launch()
        let card = app.buttons["game.twentyFortyEight"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let board = app.otherElements["board2048"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        for _ in 0..<2 { board.swipeLeft(); board.swipeUp(); board.swipeRight(); board.swipeDown() }
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The card asks before erasing the game in progress; Cancel stays on the home screen.
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.staticTexts["Start a new 2048 game?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your 2048 game in progress will be erased. This can't be undone."].exists)
        // iOS 26+ shows the dialog as a popover without a Cancel button; tapping outside dismisses it.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["confirmNewGame"].firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(board.exists)

        // Continue Playing restores it.
        app.buttons["Resume 2048"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "the saved game was restored")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Confirming starts over.
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["confirmNewGame"].firstMatch.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.isEnabled, "a new game has no moves to undo")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Resume 2048"].exists, "the erased game is no longer in progress")
    }

    /// Long-pressing a game in progress offers to discard it, after confirming.
    func testLongPressDiscardsAGameInProgress() {
        let app = launch()
        let card = app.buttons["game.twentyFortyEight"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let board = app.otherElements["board2048"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        for _ in 0..<2 { board.swipeLeft(); board.swipeUp(); board.swipeRight(); board.swipeDown() }
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let chip = app.buttons["Resume 2048"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.press(forDuration: 1.2)
        app.buttons["Discard Game"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Discard your 2048 game?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your progress will be erased. This can't be undone."].exists)
        app.buttons["confirmDiscard"].firstMatch.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 3), "the discarded game is gone from Continue Playing")

        // Opening the card now starts fresh, with no prompt.
        card.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }
}
