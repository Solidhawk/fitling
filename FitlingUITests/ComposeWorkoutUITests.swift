import XCTest

/// Training samenstellen: how long, what comes out of it, and that this is what starts.
final class ComposeWorkoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openComposer(_ extra: [String] = [], minutes: Int = 60) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL",
                               "-fitling.workoutMinutes", "\(minutes)"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        let compose = app.buttons["training.compose"]
        var swipes = 0
        while !(compose.exists && compose.isHittable) && swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        compose.tap()
        XCTAssertTrue(app.navigationBars["Training samenstellen"].waitForExistence(timeout: 10))
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
    func testTheChosenTimeIsTakenIntoTheWorkout() {
        // Not through the launch arguments: those would win over what the test picks.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        let compose = app.buttons["training.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.tap()

        let duration = app.buttons["training.compose.duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10), "No choice of how long")
        duration.tap()
        keepScreenshot(app, named: "samenstellen-keuzes")
        app.buttons["20 minuten"].tap()

        let estimate = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ongeveer 19 minuten")).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 5), "The estimate does not follow the choice")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Past er niet in")).firstMatch.exists)
        keepScreenshot(app, named: "samenstellen-20")
        app.swipeUp()
        keepScreenshot(app, named: "samenstellen-20-oefeningen")

        app.buttons["training.compose.start"].tap()
        XCTAssertTrue(app.buttons["workout.finish"].waitForExistence(timeout: 10), "The workout did not start")
        keepScreenshot(app, named: "samenstellen-gestart")
    }

    @MainActor
    func testAnHour() {
        let app = openComposer()
        XCTAssertTrue(app.buttons["training.compose.duration"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "samenstellen-60")
        app.swipeUp()
        keepScreenshot(app, named: "samenstellen-60-oefeningen")
    }

    @MainActor
    func testWhenTheFocusIsFullBeforeTheTimeIsUp() {
        let app = openComposer(minutes: 90)
        let arms = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Armen")).firstMatch
        var swipes = 0
        while !(arms.exists && arms.isHittable) && swipes < 6 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        arms.tap()
        keepScreenshot(app, named: "samenstellen-90-armen")
        // No swipe back up: with the list already at the top it closed the whole sheet (run 45159247688).
        let timeOver = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "eerder klaar")).firstMatch
        XCTAssertTrue(timeOver.waitForExistence(timeout: 5), "Nothing says the workout is shorter than asked")
        keepScreenshot(app, named: "samenstellen-90-armen-boven")
    }

    @MainActor
    func testInDarkMode() {
        let app = openComposer(["--ui-testing-dark"])
        keepScreenshot(app, named: "samenstellen-donker")
    }

    @MainActor
    func testAtTheLargestTextSize() {
        let app = openComposer(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["training.compose.duration"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "samenstellen-grootste-tekst")
    }
}
