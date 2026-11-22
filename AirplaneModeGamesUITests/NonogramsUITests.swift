import XCTest

@MainActor
final class NonogramsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchIntoHeart() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "nonograms"]
        app.launch()
        let card = app.buttons["puzzle.e-heart"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("not started"))
        card.tap()
        XCTAssertTrue(cell(app, 0, 0).waitForExistence(timeout: 5))
        return app
    }

    private func cell(_ app: XCUIApplication, _ r: Int, _ c: Int) -> XCUIElement {
        app.descendants(matching: .any)["nono.\(r).\(c)"]
    }

    private func drag(_ app: XCUIApplication, from a: (Int, Int), to b: (Int, Int)) {
        cell(app, a.0, a.1).press(forDuration: 0.05, thenDragTo: cell(app, b.0, b.1))
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    func testTapDragUndoAndCrossTool() {
        let app = launchIntoHeart()
        cell(app, 1, 0).tap()
        XCTAssertEqual(value(cell(app, 1, 0)), "Filled")

        // One stroke fills the whole row.
        drag(app, from: (2, 0), to: (2, 4))
        for c in 0..<5 { XCTAssertEqual(value(cell(app, 2, c)), "Filled") }

        // Undo removes the entire stroke.
        app.buttons["Undo"].tap()
        for c in 0..<5 { XCTAssertEqual(value(cell(app, 2, c)), "Empty") }
        XCTAssertEqual(value(cell(app, 1, 0)), "Filled")

        // Cross tool.
        let toggle = app.buttons["toolToggle"]
        XCTAssertEqual(toggle.value as? String, "Fill")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Cross")
        cell(app, 0, 0).tap()
        XCTAssertEqual(value(cell(app, 0, 0)), "Crossed out")
        // Starting a stroke on a cross with the cross tool erases it.
        cell(app, 0, 0).tap()
        XCTAssertEqual(value(cell(app, 0, 0)), "Empty")
    }

    func testCheckFlagsMistakesAndHintFixesThem() {
        let app = launchIntoHeart()
        cell(app, 0, 0).tap() // (0,0) is blank in the heart.
        app.buttons["Check"].tap()
        XCTAssertEqual(value(cell(app, 0, 0)), "Filled, mistake")
        app.buttons["Hint"].tap()
        XCTAssertEqual(value(cell(app, 0, 0)), "Crossed out")
    }

    func testSolvingRevealsPicture() {
        let app = launchIntoHeart()
        cell(app, 0, 1).tap()
        cell(app, 0, 3).tap()
        drag(app, from: (1, 0), to: (1, 4))
        drag(app, from: (2, 0), to: (2, 4))
        drag(app, from: (3, 1), to: (3, 3))
        cell(app, 4, 2).tap()

        let next = app.buttons["nextPuzzleButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Heart"].exists)
        app.buttons["All Puzzles"].tap()

        let card = app.buttons["puzzle.e-heart"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("solved: Heart"), card.label)
    }
}
