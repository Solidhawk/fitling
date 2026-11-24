import XCTest

/// Apple's accessibility audit on every tab (TASKS 7.2): contrast, labels, hit regions, traits and Dynamic
/// Type, in light, in dark and at the largest text size. All findings of a run are collected and attached as
/// one report before the test fails, so one run shows the whole list.
///
/// Left out, each checked against the screenshots of run 45243101753:
/// - "Text clipped": it flagged list labels that wrap in full (Boodschappen, Recepten, Training samenstellen)
///   and "Koolhydraten", which shrinks a little on purpose (`MacroBlocks`).
/// - Dynamic Type at the standard size: it flagged list rows that do grow; the largest-size run checks them.
/// - Dynamic Type on buttons in the navigation bar: the bars stop growing on purpose (`NavigationBarStyleTests`);
///   a long press shows the large version.
/// - Contrast without an element: only on the tabs with the 3D partner, a picture hidden from VoiceOver.
/// - Elements behind the tab bar, or behind a button bar at the bottom of a sheet (with its fade): their contrast
///   is measured against the bar instead of their own ground.
final class AccessibilityAuditTests: XCTestCase {
    private let tabs = ["Vandaag", "Training", "Menu", "Partner", "Dagdoel"]

    @MainActor
    private func ignored(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard let element = issue.element else { return issue.auditType == .contrast }
        let frame = element.frame
        if frame.intersects(app.tabBars.firstMatch.frame) { return true }
        let start = app.buttons["training.compose.start"]
        if start.exists, frame.maxY > start.frame.minY - 24 { return true }
        if issue.auditType == .dynamicType, frame.intersects(app.navigationBars.firstMatch.frame) { return true }
        return false
    }

    @MainActor
    private func audit(_ extra: [String], named name: String, types: XCUIAccessibilityAuditType) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-workout-history", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        var findings: [String] = []
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "toegankelijkheid-\(name)-\(tab)"
            shot.lifetime = .keepAlways
            add(shot)
            try app.performAccessibilityAudit(for: types) { issue in
                if self.ignored(issue, in: app) { return true }
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.identifier) \($0.frame)" } ?? "-"
                findings.append("\(tab) | \(issue.auditType.rawValue) | \(issue.compactDescription) | \(element) | \(issue.detailedDescription)")
                return true
            }
        }
        let report = XCTAttachment(string: findings.isEmpty ? "geen bevindingen" : findings.joined(separator: "\n"))
        report.name = "toegankelijkheid-\(name)"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(findings.isEmpty, "\(findings.count) findings:\n" + findings.joined(separator: "\n"))
    }

    /// One screen behind a tab: open it, audit it, and go back the way it came.
    @MainActor
    private func auditScreen(_ name: String, _ app: XCUIApplication, open: XCUIElement, close: () -> Void, findings: inout [String]) throws {
        guard open.waitForExistence(timeout: 5) else {
            findings.append("\(name) | niet bereikt")
            return
        }
        open.tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "toegankelijkheid-scherm-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        var found: [String] = []
        try app.performAccessibilityAudit(for: .all.subtracting([.textClipped, .dynamicType])) { issue in
            if self.ignored(issue, in: app) { return true }
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.identifier) \($0.frame)" } ?? "-"
            found.append("\(name) | \(issue.auditType.rawValue) | \(issue.compactDescription) | \(element) | \(issue.detailedDescription)")
            return true
        }
        findings += found
        close()
        sleep(1)
    }

    /// The screens behind the tabs: logging food, composing a workout, the shopping list, recipes, editing the
    /// partner, the account and "Over Fitling".
    @MainActor
    func testScreensBehindTheTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-workout-history", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        let back = { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let closeSheet = {
            let cancel = app.navigationBars.buttons.element(boundBy: 0)
            if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
        }
        var findings: [String] = []
        try auditScreen("loggen", app, open: app.buttons["day.add.breakfast"], close: closeSheet, findings: &findings)
        app.tabBars.buttons["Training"].tap()
        try auditScreen("samenstellen", app, open: app.buttons["training.compose"], close: closeSheet, findings: &findings)
        app.tabBars.buttons["Menu"].tap()
        try auditScreen("boodschappen", app, open: app.buttons["menu.shopping"], close: back, findings: &findings)
        try auditScreen("recepten", app, open: app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Recepten")).firstMatch, close: back, findings: &findings)
        app.tabBars.buttons["Partner"].tap()
        try auditScreen("partner-aanpassen", app, open: app.navigationBars.buttons["Aanpassen"], close: closeSheet, findings: &findings)
        app.tabBars.buttons["Dagdoel"].tap()
        try auditScreen("account", app, open: app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Account")).firstMatch, close: {}, findings: &findings)
        try auditScreen("over", app, open: app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Over Fitling")).firstMatch, close: back, findings: &findings)
        let report = XCTAttachment(string: findings.isEmpty ? "geen bevindingen" : findings.joined(separator: "\n"))
        report.name = "toegankelijkheid-schermen"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(findings.isEmpty, "\(findings.count) findings:\n" + findings.joined(separator: "\n"))
    }

    @MainActor
    func testLight() throws {
        try audit([], named: "licht", types: .all.subtracting([.textClipped, .dynamicType]))
    }

    @MainActor
    func testDark() throws {
        try audit(["--ui-testing-dark"], named: "donker", types: .all.subtracting([.textClipped, .dynamicType]))
    }

    @MainActor
    func testLargestText() throws {
        try audit(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], named: "grootste-tekst",
                  types: .all.subtracting([.textClipped]))
    }
}
