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
}
