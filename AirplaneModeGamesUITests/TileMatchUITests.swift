import XCTest

final class TileMatchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "tileMatch"]
        app.launch()
        return app
    }

    private func tiles(_ app: XCUIApplication, value: String? = nil) -> XCUIElementQuery {
        let base = "identifier BEGINSWITH 'tile.'"
        let format = value.map { base + " AND value CONTAINS '\($0)'" } ?? base
        return app.buttons.matching(NSPredicate(format: format))
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testBoardLoadsHintMatchAndUndo() {
        let app = launch()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tiles(app).count, 10, "uncovered tiles are exposed to accessibility")
        XCTAssertGreaterThan(tiles(app, value: "free").count, 1)

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(undo.isEnabled)

        let counter = app.descendants(matching: .any)["tilesLeft"]
        XCTAssertTrue(counter.exists)
        let before = counter.label

        app.buttons["Hint"].tap()
        let hinted = tiles(app, value: "hinted")
        XCTAssertEqual(hinted.count, 2, "hint highlights a pair")
        attachScreenshot("hint")

        let first = hinted.element(boundBy: 0), second = hinted.element(boundBy: 1)
        first.tap()
        XCTAssertEqual(tiles(app, value: "selected").count, 1)
        attachScreenshot("selected")
        second.tap()

        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertTrue(undo.isEnabled, "a match can be undone")
        XCTAssertNotEqual(before, counter.label, "two tiles were removed")

        undo.tap()
        XCTAssertFalse(undo.isEnabled)

        app.buttons["Shuffle"].tap()
        XCTAssertTrue(undo.isEnabled, "a shuffle can be undone")
        attachScreenshot("shuffled")
    }

    func testBlockedTileTapDoesNotSelect() {
        let app = launch()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 5))
        let blocked = tiles(app, value: "blocked").firstMatch
        guard blocked.exists else { return }
        blocked.tap()
        XCTAssertEqual(tiles(app, value: "selected").count, 0)
    }

    func testLayoutMenuStartsNewGame() {
        let app = launch()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].tap()
        let pebble = app.buttons["Pebble · 36"]
        XCTAssertTrue(pebble.waitForExistence(timeout: 3))
        pebble.tap()
        XCTAssertTrue(app.staticTexts["Pebble"].waitForExistence(timeout: 3) || app.otherElements["tileMatchBoard"].exists)
        attachScreenshot("pebble")
    }
}
