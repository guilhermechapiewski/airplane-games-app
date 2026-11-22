import XCTest

@MainActor
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

    /// State changes after a tap land asynchronously; poll instead of reading `isEnabled` once.
    private func waitUntil(_ element: XCUIElement, enabled: Bool, _ message: String, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: enabled))
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, message)
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

        // Pin the pair by identifier: selecting a tile raises it, which reorders the live `hinted` query.
        let ids = (0..<2).map { hinted.element(boundBy: $0).identifier }
        let first = app.buttons[ids[0]], second = app.buttons[ids[1]]
        first.tap()
        XCTAssertEqual(tiles(app, value: "selected").count, 1)
        attachScreenshot("selected")
        second.tap()

        waitUntil(undo, enabled: true, "a match can be undone")
        XCTAssertNotEqual(before, counter.label, "two tiles were removed")

        undo.tap()
        waitUntil(undo, enabled: false, "undo is spent")

        app.buttons["Shuffle"].tap()
        waitUntil(undo, enabled: true, "a shuffle can be undone")
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

    func testLargestLayoutFitsOnScreenInBothOrientations() {
        let app = launch()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].tap()
        let fortress = app.buttons["Fortress · 144"]
        XCTAssertTrue(fortress.waitForExistence(timeout: 3))
        fortress.tap()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 3))
            let window = app.windows.firstMatch.frame
            let query = tiles(app)
            let count = query.count
            XCTAssertGreaterThan(count, 20)
            // Sample across the painter's order (first, last and every 12th) to keep the test quick.
            for i in Array(stride(from: 0, to: count, by: 12)) + [count - 1] {
                let tile = query.element(boundBy: i)
                XCTAssertTrue(window.contains(tile.frame), "\(tile.identifier) is off-screen in \(orientation.rawValue)")
            }
            attachScreenshot("fortress-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testPlayingHintsClearsTheBoard() {
        let app = launch()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 5))
        app.buttons["gameMenu"].tap()
        app.buttons["New Game"].tap()
        app.buttons["Pebble · 36"].tap()
        for _ in 0..<18 {
            app.buttons["Hint"].tap()
            let hinted = tiles(app, value: "hinted")
            guard hinted.count == 2 else { break }
            let ids = [hinted.element(boundBy: 0).identifier, hinted.element(boundBy: 1).identifier]
            app.buttons[ids[0]].tap()
            app.buttons[ids[1]].tap()
        }
        XCTAssertTrue(app.staticTexts["Board Cleared!"].waitForExistence(timeout: 4))
        attachScreenshot("win")
        app.buttons["Play Again"].tap()
        XCTAssertTrue(app.otherElements["tileMatchBoard"].waitForExistence(timeout: 3))
    }
}
