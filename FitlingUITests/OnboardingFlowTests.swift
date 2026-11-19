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
        // A disabled button is still hittable; tapping it would silently leave the test on this step.
        XCTAssertTrue(button.isEnabled, "Verder is disabled on \(step)")
        button.tap()
    }

    /// A list only creates the rows that are on screen; at the largest text many are not. A row can
    /// also be half under the Verder bar: XCUITest still calls it hittable and taps its middle,
    /// which lands on the bar. So a row counts as reachable only when it is clear of the bar
    /// (the progress pills sit just above the button). Earlier steps stay in the navigation stack,
    /// so the list to swipe is the one of this step.
    @MainActor
    private func scrollTo(_ element: XCUIElement, onStep step: String, _ app: XCUIApplication) {
        let list = app.collectionViews["onboarding.step.\(step)"]
        let bar = app.buttons["onboarding.continue.\(step)"]
        var swipes = 0
        while !isClear(element, of: bar) && swipes < 10 {
            // Slow, so a row that was just under the bar does not shoot past the top.
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    @MainActor
    private func isClear(_ element: XCUIElement, of bar: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        guard bar.exists else { return true }
        return element.frame.maxY < bar.frame.minY - 48
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
    private func choose(_ title: String, onStep step: String, _ app: XCUIApplication) {
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        scrollTo(option, onStep: step, app)
        XCTAssertTrue(option.waitForExistence(timeout: 5), "No option \(title)")
        option.tap()
    }

    @MainActor
    private func giveConsent(_ app: XCUIApplication) {
        let toggle = app.switches["consent.agree"]
        scrollTo(toggle, onStep: "consent", app)
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

        choose("Man", onStep: "sex", app)
        keepScreenshot(app, named: "\(prefix)-3-geslacht")
        tapContinue("sex", app)

        type("180", into: "input.height", app)
        keepScreenshot(app, named: "\(prefix)-4-lengte")
        tapContinue("height", app)

        type("80", into: "input.weight", app)
        keepScreenshot(app, named: "\(prefix)-5-gewicht")
        tapContinue("weight", app)

        choose("Gemiddeld actief", onStep: "activity", app)
        keepScreenshot(app, named: "\(prefix)-6-activiteit")
        tapContinue("activity", app)

        choose("Op gewicht blijven", onStep: "goal", app)
        keepScreenshot(app, named: "\(prefix)-7-doel")
        tapContinue("goal", app)

        let kcal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2.760")).firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-8-resultaat")
        tapContinue("result", app)

        choosePartner(app, prefix: prefix)

        // Then the app opens on today; the partner and the daily target are the other tabs.
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-11-vandaag")
        app.tabBars.buttons["Partner"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["partner.hero"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-12-partner")
        app.tabBars.buttons["Dagdoel"].tap()
        XCTAssertTrue(app.navigationBars["Dagdoel"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-13-dagdoel")
    }

    /// Pip, with the name Pip filled in and "pa" typed after it.
    @MainActor
    private func choosePartner(_ app: XCUIApplication, prefix: String) {
        // The card carries the identifier; the button inside it does not.
        let pip = app.descendants(matching: .any)["partner.setup.species.pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        keepScreenshot(app, named: "\(prefix)-9-partner-kiezen")
        pip.tap()

        let list = app.collectionViews["partner.setup.list"]
        let done = app.buttons["partner.setup.done"]
        let name = app.textFields["partner.setup.name"]
        var swipes = 0
        while !isClear(name, of: done) && swipes < 10 {
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("pa")
        XCTAssertEqual(name.value as? String, "Pippa")
        keepScreenshot(app, named: "\(prefix)-10-partner-naam")
        XCTAssertTrue(done.isEnabled)
        done.tap()
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
