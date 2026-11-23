import XCTest

/// Apple's accessibility audit on every tab (TASKS 7.2): contrast, labels, hit regions, Dynamic Type and
/// clipped text, in light, in dark and at the largest text size. All findings of a run are collected and
/// attached as one report before the test fails, so one run shows the whole list.
final class AccessibilityAuditTests: XCTestCase {
    private let tabs = ["Vandaag", "Training", "Menu", "Partner", "Dagdoel"]

    @MainActor
    private func audit(_ extra: [String], named name: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-workout-history", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        var findings: [String] = []
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            try app.performAccessibilityAudit(for: .all) { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.identifier)" } ?? "-"
                findings.append("\(tab) | \(issue.auditType) | \(issue.compactDescription) | \(element)")
                return true
            }
        }
        let report = XCTAttachment(string: findings.isEmpty ? "geen bevindingen" : findings.joined(separator: "\n"))
        report.name = "toegankelijkheid-\(name)"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(findings.isEmpty, "\(findings.count) findings:\n" + findings.joined(separator: "\n"))
    }

    @MainActor
    func testLight() throws {
        try audit([], named: "licht")
    }

    @MainActor
    func testDark() throws {
        try audit(["--ui-testing-dark"], named: "donker")
    }

    @MainActor
    func testLargestText() throws {
        try audit(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], named: "grootste-tekst")
    }
}
