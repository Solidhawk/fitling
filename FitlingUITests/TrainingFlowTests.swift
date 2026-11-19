import XCTest

/// A first workout on the fake server: open a ready-made programme, start day A, log one set,
/// see the rest timer, finish.
final class TrainingFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"] + extra
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
    private func reveal(_ element: XCUIElement, inList list: String, _ app: XCUIApplication) {
        let collection = app.collectionViews[list]
        XCTAssertTrue(collection.waitForExistence(timeout: 10), "No list \(list)")
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            collection.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    @MainActor
    private func firstWorkout(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-1-overzicht")

        let program = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Full body 3×")).firstMatch
        reveal(program, inList: "training.list", app)
        program.tap()

        let start = app.buttons["training.start.0"]
        XCTAssertTrue(app.collectionViews["program.list"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-2-schema")
        reveal(start, inList: "program.list", app)
        start.tap()

        XCTAssertTrue(app.collectionViews["workout.list"].waitForExistence(timeout: 5))
        let weight = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.weight.")).firstMatch
        reveal(weight, inList: "workout.list", app)
        weight.tap()
        weight.typeText("60")
        let reps = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.reps.")).firstMatch
        reps.tap()
        if let current = reps.value as? String, !current.isEmpty, current != "Herhalingen" {
            reps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        reps.typeText("8")
        keepScreenshot(app, named: "\(prefix)-3-training")

        let log = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.log.")).firstMatch
        reveal(log, inList: "workout.list", app)
        XCTAssertTrue(log.isEnabled)
        log.tap()

        XCTAssertTrue(app.descendants(matching: .any)["workout.rest"].waitForExistence(timeout: 5))
        app.collectionViews["workout.list"].swipeDown(velocity: .fast)
        keepScreenshot(app, named: "\(prefix)-4-rust")

        app.buttons["workout.finish"].tap()
        XCTAssertTrue(app.collectionViews["workout.list"].waitForNonExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))
        // After a finished workout the next day of the programme is offered.
        XCTAssertTrue(app.buttons["training.next"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-5-volgende")
    }

    @MainActor
    func testFirstWorkout() {
        firstWorkout(launch(), prefix: "training-licht")
    }

    @MainActor
    func testFirstWorkoutInDarkMode() {
        firstWorkout(launch(["--ui-testing-dark"]), prefix: "training-donker")
    }

    @MainActor
    func testFirstWorkoutAtTheLargestTextSize() {
        firstWorkout(
            launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
            prefix: "training-grootste-tekst"
        )
    }
}
