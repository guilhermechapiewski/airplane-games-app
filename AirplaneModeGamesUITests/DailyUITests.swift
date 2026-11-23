import XCTest

@MainActor
final class DailyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Today's Sudoku from the game menu: solve it with hints, see the streak, come back to the
    /// "done for today" card, and find the daily card in Statistics.
    func testDailySudokuFromMenuToStreak() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "sudoku"]
        app.launch()
        let menu = app.buttons["gameMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["todaysPuzzle"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Daily Sudoku"].waitForExistence(timeout: 5))

        // Solve with explained hints.
        let hint = app.buttons["Hint"]
        let answer = app.buttons["hintShowAnswer"]
        let solved = app.staticTexts["Solved!"]
        XCTAssertTrue(hint.waitForExistence(timeout: 15))
        var taps = 0
        while !solved.exists && taps < 81 {
            if hint.isEnabled && hint.isHittable {
                hint.tap()
                if answer.waitForExistence(timeout: 2) { answer.tap() }
                taps += 1
            } else {
                _ = solved.waitForExistence(timeout: 0.5)
            }
        }
        XCTAssertTrue(solved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["🔥 1"].exists, "the daily result shows a one-day streak")
        app.buttons["Done"].tap()

        // Back on the regular game; today's puzzle now opens on the "done" card.
        XCTAssertTrue(app.navigationBars["Sudoku"].waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["todaysPuzzle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Today's puzzle is done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1-day streak"].exists)
        app.buttons["Back"].firstMatch.tap()

        // Statistics show the daily card.
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["Statistics"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dailyStats"].waitForExistence(timeout: 3))
    }

    /// The home card shows a "today's puzzle is waiting" badge, and the long-press menu opens it.
    func testHomeBadgeAndLongPressOpenToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let card = app.buttons["game.wordGuess"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Today's puzzle is waiting"), card.label)
        card.press(forDuration: 1.2)
        app.buttons["Today's Puzzle"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Daily Word Guess"].waitForExistence(timeout: 5))
    }
}
