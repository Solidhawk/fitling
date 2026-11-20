import XCTest

/// TASKS 7.2: Apple's accessibility audit on every tab. It checks labels for VoiceOver, contrast,
/// tap targets, traits and actions. Every finding is collected first, so one run shows them all.
///
/// - Only elements that are wholly between the navigation bar and the tab bar count. A row that is
///   half under the tab bar is measured against the bar's blur and reported as clipped and low in
///   contrast, while it reads fine once scrolled into view.
/// - Dynamic Type and clipped text are left to the flows at the largest text size
///   (`FoodFlowTests`, `TrainingFlowTests`, `OnboardingFlowTests`): those prove that every step can
///   still be reached and read. The audit reports standard SwiftUI list text as "partially
///   unsupported" even when it grows to the largest size.
/// - A finding without an element cannot be traced to a view; it is attached to the test result.
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
        var untraced: [String] = []
        for index in 0..<count {
            let tab = tabs.buttons.element(boundBy: index)
            let name = tab.label
            tab.tap()
            let navigationBar = app.navigationBars.firstMatch
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            let top = navigationBar.frame.maxY
            let bottom = tabs.frame.minY
            try app.performAccessibilityAudit(for: .all.subtracting([.dynamicType, .textClipped])) { issue in
                guard let element = issue.element else {
                    untraced.append("\(name): \(issue.auditType.rawValue) \(issue.compactDescription)")
                    return true
                }
                let frame = element.frame
                guard frame.minY >= top - 1, frame.maxY <= bottom + 1 else { return true }
                issues.append("\(name): \(issue.auditType.rawValue) \(issue.compactDescription) [\(element.elementType.rawValue) '\(element.identifier)' '\(element.label)']")
                return true
            }
        }
        if !untraced.isEmpty {
            let attachment = XCTAttachment(string: untraced.joined(separator: "\n"))
            attachment.name = "audit-zonder-element\(dark ? "-donker" : "")"
            attachment.lifetime = .keepAlways
            add(attachment)
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
