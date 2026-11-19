import XCTest

/// TASKS 7.2: Apple's accessibility audit on every tab. It checks labels for VoiceOver, contrast,
/// text that is clipped or does not grow with Dynamic Type, and tap targets. Every finding is
/// collected first, so one run shows them all.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func auditEveryTab(dark: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
            + (dark ? ["--ui-testing-dark"] : [])
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        let count = tabs.buttons.count
        XCTAssertGreaterThanOrEqual(count, 5)
        var issues: [String] = []
        for index in 0..<count {
            let tab = tabs.buttons.element(boundBy: index)
            let name = tab.label
            tab.tap()
            // Give the tab a moment to load its list.
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "-"
                issues.append("\(name): \(issue.auditType.rawValue) \(issue.compactDescription) [\(element)]")
                return true
            }
        }
        XCTAssertEqual(issues, [], issues.joined(separator: "\n"))
    }

    @MainActor
    func testEveryTabPassesTheAudit() throws {
        try auditEveryTab(dark: false)
    }

    @MainActor
    func testEveryTabPassesTheAuditInDarkMode() throws {
        try auditEveryTab(dark: true)
    }
}
