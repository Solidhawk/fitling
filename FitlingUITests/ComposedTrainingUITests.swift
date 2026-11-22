import XCTest

/// Two composed workouts in a row: both keep their name, and the next one is composed.
final class ComposedTrainingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL",
                               "-fitling.workoutMinutes", "20"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, scrollingUp: Bool = false) {
        var swipes = 0
        // Wholly above the tab bar: a row behind it counts as hittable, but the tap lands on the bar.
        while !(element.exists && element.isHittable && element.frame.maxY < app.tabBars.firstMatch.frame.minY) && swipes < 12 {
            let list = app.collectionViews["training.list"]
            if scrollingUp { list.swipeDown(velocity: .slow) } else { list.swipeUp(velocity: .slow) }
            swipes += 1
        }
    }

    /// In the composer: starts the workout and finishes it.
    @MainActor
    private func startAndFinish(_ app: XCUIApplication) {
        app.buttons["training.compose.start"].tap()
        let finish = app.buttons["workout.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "The workout did not start")
        finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openComposer(_ app: XCUIApplication) {
        let compose = app.buttons["training.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.tap()
        XCTAssertTrue(app.navigationBars["Training samenstellen"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testEachWorkoutKeepsItsNameAndTheNextIsComposed() {
        let app = launch()
        openComposer(app)
        startAndFinish(app)

        // The next workout opens the composer instead of starting a repeat.
        let next = app.buttons["training.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.label.contains("Bovenlichaam") && next.label.contains("20 minuten"), next.label)
        keepScreenshot(app, named: "volgende-1-na-bovenlichaam")
        next.tap()
        XCTAssertTrue(app.navigationBars["Training samenstellen"].waitForExistence(timeout: 10), "It repeats the last workout")
        keepScreenshot(app, named: "volgende-2-samenstellen")

        let lower = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Onderlichaam")).firstMatch
        XCTAssertTrue(lower.waitForExistence(timeout: 5))
        lower.tap()
        startAndFinish(app)

        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.label.contains("Bovenlichaam"), "Upper and lower do not take turns: \(next.label)")
        keepScreenshot(app, named: "volgende-3-om-de-beurt")

        func done(_ name: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "training.recent", name)).firstMatch
        }
        reveal(done("Bovenlichaam"), app)
        XCTAssertTrue(done("Bovenlichaam").exists, "The first workout lost its name")
        XCTAssertTrue(done("Onderlichaam").exists, "The second workout is missing")
        keepScreenshot(app, named: "volgende-4-recent")

        let program = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Samengestelde training")).firstMatch
        reveal(program, app, scrollingUp: true)
        program.tap()
        XCTAssertTrue(app.collectionViews["program.list"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "volgende-5-schema")
    }

    @MainActor
    func testTheNextWorkoutInDarkMode() {
        let app = launch(["--ui-testing-dark"])
        openComposer(app)
        startAndFinish(app)
        XCTAssertTrue(app.buttons["training.next"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "volgende-donker")
    }

    @MainActor
    func testTheNextWorkoutAtTheLargestTextSize() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openComposer(app)
        startAndFinish(app)
        XCTAssertTrue(app.buttons["training.next"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "volgende-grootste-tekst")
    }
}
