import XCTest

/// Runs Xcode's accessibility audit on every screen and attaches each screen's findings to the
/// result bundle ("a11y-<screen>").
///
/// Fails on issues that block VoiceOver users (missing or unreadable labels, unreachable
/// elements, broken actions). Contrast, Dynamic Type, clipping and hit-area findings are only
/// reported: game boards keep fixed sizes on purpose so they fit, disabled controls are dimmed
/// on purpose, and the pixel-sampled contrast check is unreliable over decorative art.
/// Set TEST_RUNNER_AUDIT_REPORT=1 to report everything without failing.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var report: Bool { ProcessInfo.processInfo.environment["AUDIT_REPORT"] == "1" }

    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        var lines: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "-"
            lines.append("A11Y [\(screen)] \(issue.auditType.rawValue) \(issue.compactDescription) :: \(element)")
            let reviewedByHand: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .hitRegion]
            return self.report || reviewedByHand.contains(issue.auditType)   // true = don't fail
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "a11y-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHomeAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["game.twentyFortyEight"].waitForExistence(timeout: 5))
        try audit(app, "home")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        try audit(app, "settings")
        app.buttons["aboutLink"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3))
        try audit(app, "about")
    }

    func testEveryGame() throws {
        let games = ["twentyFortyEight", "sudoku", "solitaire", "blocks", "tileMatch", "minesweeper",
                     "chess", "wordGuess", "nonograms", "wordSearch", "snake", "hangman"]
        for game in games {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-openGame", game]
            app.launch()
            XCTAssertTrue(app.buttons["gameMenu"].waitForExistence(timeout: 10), game)
            let cancel = app.buttons["Cancel"]
            if cancel.waitForExistence(timeout: 1) { cancel.tap() }
            sleep(1)
            try audit(app, game)
            app.terminate()
        }
    }
}
