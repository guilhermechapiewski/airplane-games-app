import XCTest

@MainActor
final class WordWheelUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// `-wordWheelScenario fixed`: center A, ring E I N P R T.
    private func launch(_ extra: [String] = ["-wordWheelScenario", "fixed"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "wordWheel"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["letter.center"].waitForExistence(timeout: 10))
        return app
    }

    private func spell(_ word: String, in app: XCUIApplication) {
        for ch in word {
            let id = ch == "a" ? "letter.center" : "letter.\(ch)"
            app.buttons[id].tap()
        }
    }

    func testEnteringWordsShufflingAndFoundList() {
        let app = launch()
        XCTAssertEqual(app.buttons["letter.center"].label, "A, center letter")

        // Missing the center letter: rejected.
        spell("tern", in: app)
        XCTAssertEqual(app.descendants(matching: .any)["currentWord"].value as? String, "T E R N")
        app.buttons["enterWord"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryMessage"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["foundCount"].label, "No words yet")

        // A valid answer.
        spell("paint", in: app)
        app.buttons["enterWord"].tap()
        let found = app.buttons["foundCount"]
        XCTAssertTrue(found.waitForLabel("1 word found", timeout: 3))

        // Delete edits the current word.
        spell("pe", in: app)
        app.buttons["deleteLetter"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["currentWord"].value as? String, "P")
        app.buttons["deleteLetter"].tap()

        // A bonus pangram.
        spell("repaint", in: app)
        app.buttons["enterWord"].tap()
        XCTAssertTrue(found.waitForLabel("2 words found", timeout: 3))

        // Shuffle moves the ring letters.
        let ringIDs = ["e", "i", "n", "p", "r", "t"].map { "letter.\($0)" }
        let before = ringIDs.map { app.buttons[$0].frame.origin }
        app.buttons["shuffle"].tap()
        let moved = NSPredicate { _, _ in ringIDs.map { app.buttons[$0].frame.origin } != before }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 3)

        // The expanded list shows both words.
        found.tap()
        XCTAssertTrue(app.descendants(matching: .any)["found.paint"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.descendants(matching: .any)["found.repaint"].value as? String, "pangram, bonus word")
    }

    func testFinishRevealsMissedAnswers() {
        let app = launch()
        spell("paint", in: app)
        app.buttons["enterWord"].tap()
        XCTAssertTrue(app.buttons["foundCount"].waitForLabel("1 word found", timeout: 3))
        app.buttons["finishWheel"].tap()
        app.buttons["Finish and Reveal Answers"].firstMatch.tap()
        XCTAssertTrue(app.buttons["seeAnswers"].waitForExistence(timeout: 3))
        app.buttons["seeAnswers"].tap()
        let missed = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'missed.'"))
        XCTAssertTrue(missed.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["missed.paint"].exists)
        XCTAssertTrue(app.buttons["newWheel"].exists)
    }

    func testResumesWhereItLeftOff() {
        var app = launch()
        spell("train", in: app)
        app.buttons["enterWord"].tap()
        XCTAssertTrue(app.buttons["foundCount"].waitForLabel("1 word found", timeout: 3))
        app.terminate()
        // Relaunch without -uiTesting so the save is kept.
        app = XCUIApplication()
        app.launchArguments = ["-openGame", "wordWheel"]
        app.launch()
        XCTAssertTrue(app.buttons["foundCount"].waitForLabel("1 word found", timeout: 10))
    }

    func testDailyWheelOpens() {
        let app = launch(["-daily"])
        XCTAssertTrue(app.navigationBars["Daily Word Wheel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wordWheelProgress"].exists)
        app.buttons["shuffle"].tap()
    }

    /// The shared audit test predates this game; audit its screen here too.
    func testAccessibilityAudit() throws {
        let app = launch(["-wordWheelScenario", "demo"])
        sleep(1)
        try app.performAccessibilityAudit { issue in
            let reviewedByHand: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .hitRegion]
            return reviewedByHand.contains(issue.auditType)
        }
    }
}

private extension XCUIElement {
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
