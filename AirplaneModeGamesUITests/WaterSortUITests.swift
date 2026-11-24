import XCTest

@MainActor
final class WaterSortUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "waterSort"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements["waterSortBoard"].waitForExistence(timeout: 10))
        return app
    }

    private func tube(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.descendants(matching: .any)["tube.\(n)"]
    }

    private func tubes(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tube.'"))
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    private func wait(_ element: XCUIElement, _ format: String, _ message: String, timeout: TimeInterval = 5) {
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)],
                                      timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The hint names a pour; making it counts as a move and clears the hint.
    func testHintSuggestsAPour() {
        let app = launch()
        XCTAssertEqual(tubes(app).count, 5)
        app.buttons["hintButton"].tap()
        let tip = app.descendants(matching: .any)["hintTip"]
        XCTAssertTrue(tip.waitForExistence(timeout: 30), "the suggested pour is spelled out")
        attachScreenshot("hint")
        // "Pour tube 2 into tube 4."
        let numbers = tip.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, tip.label)
        tube(app, numbers[0]).tap()
        tube(app, numbers[1]).tap()
        wait(app.buttons["Undo"], "enabled == true", "the suggested pour was legal")
        XCTAssertTrue(app.descendants(matching: .any)["movesCount"].label.contains("1"))
        XCTAssertTrue(tip.waitForNonExistence(timeout: 3), "a pour clears the hint")
    }

    /// Finds a legal first pour on the level and makes it: pick a tube, then the first empty one.
    func testPourUndoAndExtraTube() {
        let app = launch()
        XCTAssertEqual(tubes(app).count, 5, "level 1: three colors and two empty tubes")
        XCTAssertTrue(value(tube(app, 1)).hasPrefix("4 layers: from bottom"))
        XCTAssertEqual(value(tube(app, 4)), "empty")

        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled)
        let moves = app.descendants(matching: .any)["movesCount"]
        XCTAssertTrue(moves.label.contains("0"))

        tube(app, 1).tap()
        XCTAssertTrue(tube(app, 1).isSelected, "a tapped tube is picked up")
        attachScreenshot("picked")
        tube(app, 4).tap()
        wait(tube(app, 4), "value BEGINSWITH '1 layer' OR value BEGINSWITH '2 layers'", "liquid poured into the empty tube")
        XCTAssertFalse(tube(app, 1).isSelected)
        wait(undo, "enabled == true", "a pour can be undone")
        XCTAssertTrue(moves.label.contains("1"))

        undo.tap()
        wait(tube(app, 4), "value == 'empty'", "undo pours it back")
        wait(undo, "enabled == false", "nothing left to undo")

        let extra = app.buttons["Extra Tube"]
        XCTAssertTrue(extra.isEnabled)
        extra.tap()
        wait(extra, "enabled == false", "the extra tube is used once per level")
        XCTAssertEqual(tubes(app).count, 6)
        attachScreenshot("extra-tube")

        app.buttons["Restart"].tap()
        wait(extra, "enabled == true", "restart gives the extra tube back")
        XCTAssertEqual(tubes(app).count, 5)
    }

    /// With the real pour animation, the next move can start while a pour is still in the air.
    func testAnimatedPoursChain() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-fullMotion", "-openGame", "waterSort"]
        app.launch()
        XCTAssertTrue(app.otherElements["waterSortBoard"].waitForExistence(timeout: 10))
        tube(app, 1).tap()
        tube(app, 4).tap()
        attachScreenshot("pouring")
        tube(app, 2).tap()
        tube(app, 5).tap()
        attachScreenshot("pouring-second")
        wait(tube(app, 5), "value != 'empty'", "the second pour lands too")
        XCTAssertNotEqual(value(tube(app, 4)), "empty")
        attachScreenshot("after-pours")
    }

    func testInvalidPourKeepsTheBoard() {
        let app = launch()
        // Tubes 1–3 are full: nothing can be poured into them.
        let before = value(tube(app, 2))
        tube(app, 1).tap()
        tube(app, 2).tap()
        XCTAssertEqual(value(tube(app, 2)), before)
        XCTAssertFalse(tube(app, 1).isSelected, "the tube is put back")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    func testSolvingAdvancesToNextLevel() {
        let app = launch(["-waterSortScenario", "nearlySolved"])
        let level = app.descendants(matching: .any)["levelNumber"]
        XCTAssertTrue(level.label.contains("1"))
        tube(app, 3).tap()
        tube(app, 2).tap()
        XCTAssertTrue(app.staticTexts["Sorted!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Level 1 solved in 1 move."].exists)
        attachScreenshot("win")
        app.buttons["Next Level"].tap()
        wait(level, "label CONTAINS '2'", "the next level opens")
        XCTAssertEqual(tubes(app).count, 5, "level 2: three colors and two empty tubes")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    func testDailyOpensAndRecordsTheStreak() {
        let app = launch(["-daily", "-waterSortScenario", "nearlySolved"])
        XCTAssertTrue(app.navigationBars["Daily Water Sort"].exists || app.staticTexts["Daily Water Sort"].exists)
        tube(app, 3).tap()
        tube(app, 2).tap()
        XCTAssertTrue(app.staticTexts["Sorted!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '🔥 1'")).firstMatch.exists
                      || app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '🔥 1'")).firstMatch.exists,
                      "streak pill")
        attachScreenshot("daily-win")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["game.waterSort"].waitForExistence(timeout: 5), "back home")
    }

    func testDailyPuzzleSize() {
        let app = launch(["-daily"])
        let count = tubes(app).count
        XCTAssertTrue((10...11).contains(count), "8–9 colors plus two empty tubes, got \(count)")
        attachScreenshot("daily")
    }

    func testAccessibilityAudit() throws {
        let app = launch(["-waterSortLevel", "40"])
        try audit(app)
    }

    /// Same policy as `AccessibilityAuditTests`.
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let reviewedByHand: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .hitRegion]
            return reviewedByHand.contains(issue.auditType)
        }
    }
}
