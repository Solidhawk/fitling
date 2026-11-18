import XCTest

/// Walks the real screens on the fake auth (`--ui-testing`) and keeps a screenshot of every step,
/// so the screens can be reviewed without a Mac.
final class OnboardingFlowTests: XCTestCase {
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

    @MainActor
    private func tapContinue(_ app: XCUIApplication) {
        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, "Verder is not reachable")
        button.tap()
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
        XCTAssertTrue(option.waitForExistence(timeout: 5), "No option \(title)")
        option.tap()
    }

    @MainActor
    private func giveConsent(_ app: XCUIApplication) {
        let toggle = app.switches["consent.agree"]
        // At the largest text size the consent text is taller than the screen; the form only creates
        // the switch row once it scrolls into view.
        var swipes = 0
        while !toggle.exists && swipes < 10 {
            app.collectionViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        if toggle.value as? String == "0" { toggle.switches.firstMatch.tap() }
    }

    @MainActor
    func testWelcomeScreen() {
        let app = launch(["--ui-testing-signed-out"])
        XCTAssertTrue(app.buttons["welcome.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.google"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["welcome.apple"].exists)
        keepScreenshot(app, named: "01-welkom")
    }

    @MainActor
    func testOnboardingToTargets() {
        let app = launch(["--ui-testing"])
        keepScreenshot(app, named: "02-toestemming")
        giveConsent(app)
        tapContinue(app)

        // The date picker starts thirty years back, which is the age the expected target assumes.
        keepScreenshot(app, named: "03-geboortedatum")
        tapContinue(app)

        choose("Man", app)
        keepScreenshot(app, named: "04-geslacht")
        tapContinue(app)

        type("180", into: "input.height", app)
        keepScreenshot(app, named: "05-lengte")
        tapContinue(app)

        type("80", into: "input.weight", app)
        keepScreenshot(app, named: "06-gewicht")
        tapContinue(app)

        choose("Gemiddeld actief", app)
        keepScreenshot(app, named: "07-activiteit")
        tapContinue(app)

        choose("Op gewicht blijven", app)
        keepScreenshot(app, named: "08-doel")
        tapContinue(app)

        let kcal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2.760")).firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: 5))
        keepScreenshot(app, named: "09-dagdoel-resultaat")
        tapContinue(app)

        XCTAssertTrue(app.navigationBars["Dagdoel"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "10-dagdoel")
    }

    @MainActor
    func testOnboardingDarkMode() {
        let app = launch(["--ui-testing", "--ui-testing-dark"])
        keepScreenshot(app, named: "11-donker-toestemming")
        giveConsent(app)
        tapContinue(app)
        keepScreenshot(app, named: "12-donker-geboortedatum")

        let welcome = launch(["--ui-testing-signed-out", "--ui-testing-dark"])
        XCTAssertTrue(welcome.buttons["welcome.email"].waitForExistence(timeout: 5))
        keepScreenshot(welcome, named: "13-donker-welkom")
    }

    @MainActor
    func testLargestTextKeepsContinueReachable() {
        let app = launch(["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        keepScreenshot(app, named: "14-grootste-tekst-toestemming")
        giveConsent(app)
        tapContinue(app)
        keepScreenshot(app, named: "15-grootste-tekst-geboortedatum")
        tapContinue(app)
        XCTAssertTrue(app.buttons["onboarding.continue"].isHittable)
    }
}
