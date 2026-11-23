import XCTest

@MainActor
final class SudokuUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func cell(_ app: XCUIApplication, _ r: Int, _ c: Int) -> XCUIElement {
        app.descendants(matching: .any)["sudoku.cell.\(r).\(c)"]
    }

    /// The first cell whose accessibility value says it is empty.
    private func firstEmptyCell(_ app: XCUIApplication) -> XCUIElement? {
        for r in 0..<9 {
            for c in 0..<9 where (cell(app, r, c).value as? String) == "Empty" {
                return cell(app, r, c)
            }
        }
        return nil
    }

    /// A digit whose pad key is still enabled.
    private func availableDigit(_ app: XCUIApplication) -> Int {
        (1...9).first { app.buttons["sudoku.pad.\($0)"].isEnabled } ?? 5
    }

    func testEnterDigitNotesHintAndHowToPlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "sudoku"]
        app.launch()

        XCTAssertTrue(cell(app, 0, 0).waitForExistence(timeout: 10))
        // Wait until the puzzle has been generated (some cells are given).
        let generated = NSPredicate { _, _ in
            (0..<9).contains { (self.cell(app, 0, $0).value as? String)?.contains("given") == true }
        }
        let ready = expectation(for: generated, evaluatedWith: nil)
        wait(for: [ready], timeout: 20)

        // Select an empty cell and enter a digit.
        let target = try XCTUnwrap(firstEmptyCell(app))
        target.tap()
        let digit = availableDigit(app)
        app.buttons["sudoku.pad.\(digit)"].tap()
        let value = target.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("\(digit)"), "value: \(value)")
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        attach(app, "digit")

        // Notes mode: the next digit becomes a pencil mark.
        let notesCell = try XCTUnwrap(firstEmptyCell(app))
        notesCell.tap()
        app.buttons["sudoku.notes"].tap()
        XCTAssertEqual(app.buttons["sudoku.notes"].value as? String, "On")
        let noteDigit = availableDigit(app)
        app.buttons["sudoku.pad.\(noteDigit)"].tap()
        XCTAssertEqual(notesCell.value as? String, "Notes \(noteDigit)")
        attach(app, "notes")

        // Undo removes the note again.
        app.buttons["Undo"].tap()
        XCTAssertEqual(notesCell.value as? String, "Empty")
        app.buttons["sudoku.notes"].tap()
        XCTAssertEqual(app.buttons["sudoku.notes"].value as? String, "Off")

        // A hint explains first; closing it changes nothing.
        app.buttons["Hint"].tap()
        let explanation = app.staticTexts["hintExplanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 3))
        XCTAssertFalse(explanation.label.isEmpty)
        attach(app, "hint")
        app.buttons["hintClose"].tap()
        XCTAssertTrue(explanation.waitForNonExistence(timeout: 3))

        // Show Answer fills the explained square.
        app.buttons["Hint"].tap()
        XCTAssertTrue(app.buttons["hintShowAnswer"].waitForExistence(timeout: 3))
        // The hint selects its square (it may be fixing the digit typed above, so check that square).
        let hinted = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sudoku.cell.' AND selected == true")).firstMatch
        XCTAssertTrue(hinted.exists)
        app.buttons["hintShowAnswer"].tap()
        XCTAssertTrue(app.buttons["hintShowAnswer"].waitForNonExistence(timeout: 3))
        XCTAssertTrue((hinted.value as? String)?.contains("from hint") == true, "the explained square was filled")

        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
    }

    func testHintsSolveThePuzzleAndShowTheWinCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "sudoku"]
        app.launch()

        let hint = app.buttons["Hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        let solved = app.staticTexts["Solved!"]
        var taps = 0
        let answer = app.buttons["hintShowAnswer"]
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
        attach(app, "win")
        XCTAssertTrue(app.buttons["Play Again"].exists)
        app.buttons["Play Again"].tap()
        XCTAssertFalse(solved.waitForExistence(timeout: 2))
    }
}
