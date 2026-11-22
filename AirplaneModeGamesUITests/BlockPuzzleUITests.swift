import XCTest

@MainActor
final class BlockPuzzleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "blocks"]
        app.launch()
        return app
    }

    private func score(_ app: XCUIApplication) -> Int {
        let pill = app.descendants(matching: .any)["blocksScore"]
        return Int(pill.value as? String ?? "") ?? -1
    }

    func testTapToPlaceAndDragToPlace() {
        let app = launch()
        let board = app.descendants(matching: .any)["blocksBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(score(app), 0)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)

        // Tap-to-place: select a piece, then tap a cell in the middle of an empty board.
        app.descendants(matching: .any)["traySlot.0"].tap()
        app.descendants(matching: .any)["cell.3.3"].tap()
        let afterTap = score(app)
        XCTAssertGreaterThan(afterTap, 0)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)

        // Drag-to-place: the piece floats above the finger, so release a bit below the target.
        let slot = app.descendants(matching: .any)["traySlot.1"]
        let target = app.descendants(matching: .any)["cell.7.6"]
        let start = slot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        let afterDrag = score(app)
        XCTAssertGreaterThan(afterDrag, afterTap)

        // Undo restores the previous score.
        app.buttons["Undo"].tap()
        XCTAssertEqual(score(app), afterTap)
    }

    func testRulesSheetOpens() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["blocksBoard"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
    }
}
