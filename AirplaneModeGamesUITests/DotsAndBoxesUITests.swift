import XCTest

@MainActor
final class DotsAndBoxesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "dotsAndBoxes"]
        app.launch()
        return app
    }

    private func startGame(_ app: XCUIApplication, opponent: String, size: Int, level: Int? = nil) {
        let card = app.buttons["setup.opponent.\(opponent)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "setup sheet should appear on first launch")
        card.tap()
        app.buttons["setup.size.\(size)"].tap()
        if let level { app.buttons["setup.level.\(level)"].tap() }
        app.buttons["setup.start"].tap()
        XCTAssertTrue(element(app, "dotsBoard").waitForExistence(timeout: 5))
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func draw(_ app: XCUIApplication, _ id: String) {
        let line = element(app, "line.\(id)")
        XCTAssertTrue(line.waitForExistence(timeout: 5), "line \(id) should be open")
        line.tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 3), "line \(id) should be drawn")
    }

    private func openLineCount(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'line.'")).count
    }

    func testPassAndPlayClaimTurnsAndUndo() {
        let app = launch()
        startGame(app, opponent: "friend", size: 3)
        let status = element(app, "turnStatus")
        XCTAssertEqual(status.label, "Player 1's turn")
        XCTAssertEqual(openLineCount(app), 24)

        draw(app, "h.0.0")                      // Player 1
        XCTAssertEqual(status.label, "Player 2's turn")
        draw(app, "h.1.0")                      // Player 2
        draw(app, "v.0.0")                      // Player 1: box (0,0) now has three sides
        XCTAssertEqual(status.label, "Player 2's turn")
        draw(app, "v.0.1")                      // Player 2 closes it

        let box = element(app, "box.0.0")
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        XCTAssertEqual(box.value as? String, "Player 2's")
        XCTAssertEqual(element(app, "score.two").value as? String, "1 box, to move")
        XCTAssertEqual(status.label, "Player 2 — go again", "claiming a box earns another move")

        // Undo takes back the closing line only.
        app.buttons["undo"].tap()
        XCTAssertTrue(box.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element(app, "line.v.0.1").exists)
        XCTAssertEqual(element(app, "score.two").value as? String, "0 boxes, to move")
        XCTAssertEqual(status.label, "Player 2's turn")
    }

    func testHintSuggestsTakingAFreeBox() {
        let app = launch()
        startGame(app, opponent: "friend", size: 3)
        let hint = app.buttons["hint"]
        XCTAssertTrue(hint.isEnabled)

        // An opening hint is a safe line.
        hint.tap()
        let banner = element(app, "hintBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.label, "Hint: Safe line. It doesn't give away a box.")
        app.buttons["hintClose"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))

        draw(app, "h.0.0")                      // Player 1
        draw(app, "h.1.0")                      // Player 2
        draw(app, "v.0.0")                      // Player 1 leaves box (0,0) on three sides
        hint.tap()                              // Player 2 asks
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.hasPrefix("Hint: Take this box."), banner.label)
        XCTAssertEqual(element(app, "line.v.0.1").value as? String, "Hint, completes a box")

        // Drawing it clears the hint.
        draw(app, "v.0.1")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
        XCTAssertEqual(element(app, "box.0.0").value as? String, "Player 2's")
    }

    func testComputerReplies() {
        let app = launch()
        startGame(app, opponent: "computer", size: 3, level: 1)
        let status = element(app, "turnStatus")
        XCTAssertEqual(status.label, "Your turn")
        XCTAssertFalse(app.buttons["undo"].isEnabled)

        draw(app, "h.0.0")
        // The computer draws a line of its own, then it's the player's turn again.
        let replied = expectation(for: NSPredicate(format: "count == 22"),
                                  evaluatedWith: app.descendants(matching: .any)
                                    .matching(NSPredicate(format: "identifier BEGINSWITH 'line.'")))
        wait(for: [replied], timeout: 10)
        XCTAssertEqual(status.label, "Your turn")

        // Undo takes back both the reply and the player's line.
        app.buttons["undo"].tap()
        XCTAssertTrue(element(app, "line.h.0.0").waitForExistence(timeout: 3))
        XCTAssertEqual(openLineCount(app), 24)
        XCTAssertFalse(app.buttons["undo"].isEnabled)
    }

    func testAccessibilityAudit() throws {
        let app = launch()
        startGame(app, opponent: "friend", size: 4)
        draw(app, "h.0.0")
        draw(app, "h.1.0")
        draw(app, "v.0.0")
        draw(app, "v.0.1")
        try app.performAccessibilityAudit { issue in
            // Fixed-size boards and dimmed controls are reviewed by hand (as in AccessibilityAuditTests).
            let reviewedByHand: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .hitRegion]
            return reviewedByHand.contains(issue.auditType)
        }
    }
}
