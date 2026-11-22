import XCTest

@MainActor
final class MinesweeperUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "minesweeper"]
        app.launch()
        return app
    }

    private func cell(_ app: XCUIApplication, _ r: Int, _ c: Int) -> XCUIElement {
        app.descendants(matching: .any)["cell.\(r).\(c)"]
    }

    private func firstHiddenCell(_ app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'cell.' AND value == 'Hidden'")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func testFirstTapOpensAreaAndLongPressFlags() {
        let app = launch()
        let center = cell(app, 4, 4)
        XCTAssertTrue(center.waitForExistence(timeout: 5))
        XCTAssertEqual(center.value as? String, "Hidden")

        center.tap()
        // The first tap is always safe and opens an empty area.
        XCTAssertTrue(NSPredicate(format: "value == 'Empty'").evaluate(with: center) ||
                      wait(for: center, value: "Empty"))
        XCTAssertNotEqual(cell(app, 4, 5).value as? String, "Hidden")

        let hidden = firstHiddenCell(app)
        XCTAssertTrue(hidden.exists, "a beginner board can't be cleared by one tap… usually")
        let id = hidden.identifier
        hidden.press(forDuration: 0.8)
        XCTAssertTrue(wait(for: app.descendants(matching: .any)[id], value: "Flagged"))
        XCTAssertTrue(app.descendants(matching: .any)["minesLeft"].label.contains("9"))

        // Long-pressing again removes the flag.
        app.descendants(matching: .any)[id].press(forDuration: 0.8)
        XCTAssertTrue(wait(for: app.descendants(matching: .any)[id], value: "Hidden"))
    }

    func testFlagModeToggle() {
        let app = launch()
        let toggle = app.buttons["modeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Reveal")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Flag")

        let corner = cell(app, 0, 0)
        corner.tap()
        XCTAssertTrue(wait(for: corner, value: "Flagged"))
        corner.tap()
        XCTAssertTrue(wait(for: corner, value: "Hidden"))

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Reveal")
    }

    func testLevelMenuAndZoom() {
        let app = launch()
        let menu = app.buttons["levelMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(cell(app, 8, 8).waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["zoomButton"].exists, "beginner fits without zoom")
        menu.tap()
        app.buttons["Expert · 99 mines"].tap()
        XCTAssertTrue(cell(app, 29, 15).waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["minesLeft"].label.contains("99"))

        let zoom = app.buttons["zoomButton"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        XCTAssertEqual(zoom.label, "Zoom")
        zoom.tap()
        XCTAssertTrue(app.buttons["Fit"].waitForExistence(timeout: 3))
        // Tapping while zoomed still reveals the cell under the finger.
        let target = cell(app, 15, 8)
        target.tap()
        XCTAssertTrue(wait(for: target, notValue: "Hidden"))
        app.buttons["Fit"].tap()
        XCTAssertTrue(app.buttons["Zoom"].waitForExistence(timeout: 3))
    }

    @discardableResult
    private func wait(for element: XCUIElement, value: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func wait(for element: XCUIElement, notValue: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", notValue), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
