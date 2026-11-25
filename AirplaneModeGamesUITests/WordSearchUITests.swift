import XCTest

@MainActor
final class WordSearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-openGame", "wordSearch", "-wordSearch.difficulty", "easy"] + extra
        app.launch()
        return app
    }

    func testScreenLoadsWithGridAndWords() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["wordSearchGrid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["cell.0.0"].exists || app.descendants(matching: .any)["cell.0.0"].exists)
        let words = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'word.'"))
        XCTAssertEqual(words.count, 6)
        app.buttons["Hint"].tap()
    }

    /// The clock stays stopped under How to Play, even after leaving the app and coming back.
    func testClockStaysPausedUnderRulesAfterReturningToTheApp() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["wordSearchGrid"].waitForExistence(timeout: 5))
        sleep(2)
        let before = seconds(app)
        app.buttons["gameMenu"].tap()
        app.buttons["How to Play"].tap()
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        sleep(10)
        app.swipeDown(velocity: .fast)
        XCTAssertLessThan(seconds(app) - before, 6, "the clock ran while How to Play was open")
    }

    /// Seconds shown by the Time pill ("TIME, 0:05").
    private func seconds(_ app: XCUIApplication) -> Int {
        let label = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'time,'")).firstMatch.label
        let parts = label.split(separator: " ").last?.split(separator: ":").compactMap { Int($0) } ?? []
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Reads the grid, finds the first listed word itself, and drags across it.
    func testDragSelectsAWord() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["wordSearchGrid"].waitForExistence(timeout: 5))
        let size = 8
        var grid: [[Character]] = []
        for r in 0..<size {
            var row: [Character] = []
            for c in 0..<size {
                let label = app.descendants(matching: .any)["cell.\(r).\(c)"].label.lowercased()
                row.append(label.first ?? "?")
            }
            grid.append(row)
        }
        let wordElement = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'word.'")).firstMatch
        let word = Array(wordElement.identifier.dropFirst("word.".count))
        XCTAssertEqual(wordElement.value as? String, "not found")

        // Easy puzzles run right or down only.
        var span: ((Int, Int), (Int, Int))?
        search: for r in 0..<size {
            for c in 0..<size {
                if c + word.count <= size, (0..<word.count).allSatisfy({ grid[r][c + $0] == word[$0] }) {
                    span = ((r, c), (r, c + word.count - 1)); break search
                }
                if r + word.count <= size, (0..<word.count).allSatisfy({ grid[r + $0][c] == word[$0] }) {
                    span = ((r, c), (r + word.count - 1, c)); break search
                }
            }
        }
        let (start, end) = try XCTUnwrap(span, "word \(String(word)) not found in grid")
        let from = app.descendants(matching: .any)["cell.\(start.0).\(start.1)"]
        let to = app.descendants(matching: .any)["cell.\(end.0).\(end.1)"]
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let found = NSPredicate(format: "value == 'found'")
        expectation(for: found, evaluatedWith: wordElement)
        waitForExpectations(timeout: 3)
    }
}
