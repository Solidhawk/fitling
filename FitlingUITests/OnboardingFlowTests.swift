import XCTest

/// Walks the real screens on the fake auth and the fake server (`--ui-testing`) and keeps a
/// screenshot of every step, so the screens can be reviewed without a Mac.
final class OnboardingFlowTests: XCTestCase {
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        return app
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Each step has its own Verder button; earlier steps stay in the navigation stack.
    @MainActor
    private func tapContinue(_ step: String, _ app: XCUIApplication) {
        let button = app.buttons["onboarding.continue.\(step)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let hittable = NSPredicate(format: "hittable == true")
        let reachable = XCTNSPredicateExpectation(predicate: hittable, object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [reachable], timeout: 5), .completed, "Verder is not reachable on \(step)")
        button.tap()
    }

    /// A list only creates the rows that are on screen; at the largest text many are not.
    @MainActor
    private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 10 {
            app.collectionViews.firstMatch.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func type(_ text: String, into identifier: String, _ app: XCUIApplication) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    /// Picker rows are buttons whose label starts with the option title (a detail line may follow).
    @MainActor
    private func choose(_ title: String, _ app: XCUIApplication) {
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        scrollTo(option, app)
        XCTAssertTrue(option.waitForExistence(timeout: 5), "No option \(title)")
        option.tap()
    }

    @MainActor
    private func giveConsent(_ app: XCUIApplication) {
        let toggle = app.switches["consent.agree"]
        scrollTo(toggle, app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        if toggle.value as? String == "0" { toggle.switches.firstMatch.tap() }
    }

    /// All eight steps to the daily target, with a screenshot of each.
    @MainActor
    private func walkThroughOnboarding(_ app: XCUIApplication, prefix: String) {
        keepScreenshot(app, named: "\(prefix)-1-toestemming")
        giveConsent(app)
        tapContinue("consent", app)

        // The date picker starts thirty years back, which is the age the expected target assumes.
        keepScreenshot(app, named: "\(prefix)-2-geboortedatum")
        tapContinue("birthDate", app)

        choose("Man", app)
        keepScreenshot(app, named: "\(prefix)-3-geslacht")
        tapContinue("sex", app)

        type("180", into: "input.height", app)
        keepScreenshot(app, named: "\(prefix)-4-lengte")
        tapContinue("height", app)

        type("80", into: "input.weight", app)
        keepScreenshot(app, named: "\(prefix)-5-gewicht")
        tapContinue("weight", app)

        choose("Gemiddeld actief", app)
        keepScreenshot(app, named: "\(prefix)-6-activiteit")
        tapContinue("activity", app)

        choose("Op gewicht blijven", app)
        keepScreenshot(app, named: "\(prefix)-7-doel")
        tapContinue("goal", app)

        let kcal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2.760")).firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-8-resultaat")
        tapContinue("result", app)

        XCTAssertTrue(app.navigationBars["Dagdoel"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-9-dagdoel")
    }

    @MainActor
    func testWelcomeScreen() {
        let app = launch(["--ui-testing-signed-out"])
        XCTAssertTrue(app.buttons["welcome.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["welcome.apple"].exists)
        keepScreenshot(app, named: "licht-0-welkom")

        let dark = launch(["--ui-testing-signed-out", "--ui-testing-dark"])
        XCTAssertTrue(dark.buttons["welcome.email"].waitForExistence(timeout: 5))
        keepScreenshot(dark, named: "donker-0-welkom")

        let largest = launch(["--ui-testing-signed-out"] + Self.largestText)
        XCTAssertTrue(largest.buttons["welcome.email"].waitForExistence(timeout: 5))
        keepScreenshot(largest, named: "grootste-tekst-0-welkom")
    }

    @MainActor
    func testOnboardingToTargets() {
        walkThroughOnboarding(launch(["--ui-testing"]), prefix: "licht")
    }

    @MainActor
    func testOnboardingDarkMode() {
        walkThroughOnboarding(launch(["--ui-testing", "--ui-testing-dark"]), prefix: "donker")
    }

    @MainActor
    func testOnboardingAtTheLargestTextSize() {
        walkThroughOnboarding(launch(["--ui-testing"] + Self.largestText), prefix: "grootste-tekst")
    }
}
