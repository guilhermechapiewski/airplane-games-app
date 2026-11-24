import XCTest

@MainActor
final class SnakeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "snake"]
        app.launch()
        return app
    }

    func testPlayPauseAndResume() {
        let app = launch()
        let board = app.descendants(matching: .any)["snakeBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        // Pick the relaxed speed on the ready card, then start.
        app.buttons["Relaxed"].tap()
        app.buttons["snakePlay"].tap()

        // After the 3-2-1 countdown the snake runs.
        let pause = app.buttons["snakePause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        sleep(2)
        XCTAssertEqual(pause.label, "Pause")

        pause.tap()
        let resume = app.buttons["snakeResume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertFalse(resume.waitForExistence(timeout: 1))
        // Steer away from the right-hand wall.
        board.swipeUp()
        XCTAssertEqual(pause.label, "Pause")

        // A swipe from the left screen edge steers instead of going back to the home screen.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.01, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertTrue(pause.exists, "an edge swipe went back to the home screen")
    }

    func testDPadToggleAndRules() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["snakeBoard"].waitForExistence(timeout: 5))
        app.buttons["D-Pad"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Up"].waitForExistence(timeout: 2))
        // Steering with the pad starts a fresh game.
        app.descendants(matching: .any)["Up"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["D-Pad"].tap()

        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
    }

    /// The start card offers the slowest speed and bigger boards, and the header shows the size.
    func testSlowSpeedAndHugeBoard() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["snakeBoard"].waitForExistence(timeout: 5))
        app.buttons["Slow"].tap()
        app.buttons["Huge 25²"].tap()
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "ready-card"
        ready.lifetime = .keepAlways
        add(ready)
        XCTAssertTrue(app.staticTexts["Walls · 25×25"].exists || app.staticTexts["Wrap-around · 25×25"].exists)
        app.buttons["snakePlay"].tap()
        XCTAssertTrue(app.buttons["snakePause"].waitForExistence(timeout: 3))
        sleep(3)
        let playing = XCTAttachment(screenshot: app.screenshot())
        playing.name = "huge-board"
        playing.lifetime = .keepAlways
        add(playing)
        XCTAssertEqual(app.buttons["snakePause"].label, "Pause", "the snake is still alive at slow speed")
    }
}
