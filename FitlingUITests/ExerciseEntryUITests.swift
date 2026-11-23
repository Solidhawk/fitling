import XCTest

/// The exercise screen, with its animation, from wherever an exercise is shown: when composing a workout, in a
/// programme and during a workout. Not only from "Per oefening", which lists only exercises already done (UNFORGET S27).
final class ExerciseEntryUITests: XCTestCase {
    private let benchPress = "f81b4810-0ad3-5c0d-b9ac-36b63d8358ca"
    private let backSquat = "f442b2ea-a4ce-5f40-b594-83f5c99dc2f0"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL",
                               "-fitling.workoutMinutes", "60"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
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
    private func reveal(_ element: XCUIElement, in list: XCUIElement, _ app: XCUIApplication) {
        var swipes = 0
        // Wholly above the tab bar: a row behind it counts as hittable, but the tap lands on the bar.
        while !(element.exists && element.isHittable && (!app.tabBars.firstMatch.exists || element.frame.maxY < app.tabBars.firstMatch.frame.minY))
            && swipes < 12 {
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    @MainActor
    private func expectTheExerciseScreen(_ app: XCUIApplication, _ name: String) {
        XCTAssertTrue(app.buttons["exercise.animation"].waitForExistence(timeout: 10), "No exercise screen with its animation")
        XCTAssertTrue(app.navigationBars[name].exists || app.staticTexts[name].exists, "Not the screen of \(name)")
    }

    @MainActor
    func testFromComposingAWorkout() {
        let app = launch()
        app.buttons["training.compose"].tap()
        XCTAssertTrue(app.navigationBars["Training samenstellen"].waitForExistence(timeout: 10))
        let row = app.buttons["training.compose.exercise.\(benchPress)"]
        reveal(row, in: app.collectionViews.firstMatch, app)
        XCTAssertTrue(row.exists, "The exercise in the composed workout cannot be opened")
        row.tap()
        expectTheExerciseScreen(app, "Bankdrukken")
        keepScreenshot(app, named: "oefening-uit-samenstellen")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["training.compose.start"].waitForExistence(timeout: 5), "Not back at composing")
    }

    @MainActor
    func testFromAProgramme() {
        let app = launch()
        let program = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Full body 3×")).firstMatch
        reveal(program, in: app.collectionViews["training.list"], app)
        program.tap()
        XCTAssertTrue(app.collectionViews["program.list"].waitForExistence(timeout: 5))
        let row = app.buttons["program.exercise.\(backSquat)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The exercise in the programme cannot be opened")
        keepScreenshot(app, named: "oefening-schema")
        row.tap()
        expectTheExerciseScreen(app, "Squat met halter")
        keepScreenshot(app, named: "oefening-uit-schema")
    }

    @MainActor
    func testDuringAWorkout() {
        let app = launch()
        let program = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Full body 3×")).firstMatch
        reveal(program, in: app.collectionViews["training.list"], app)
        program.tap()
        let start = app.buttons["training.start.0"]
        XCTAssertTrue(app.collectionViews["program.list"].waitForExistence(timeout: 5))
        reveal(start, in: app.collectionViews["program.list"], app)
        start.tap()
        XCTAssertTrue(app.collectionViews["workout.list"].waitForExistence(timeout: 10))

        let explain = app.buttons["workout.exercise.\(backSquat)"]
        XCTAssertTrue(explain.waitForExistence(timeout: 5), "The exercise in the workout cannot be opened")
        keepScreenshot(app, named: "oefening-training")
        explain.tap()
        expectTheExerciseScreen(app, "Squat met halter")
        keepScreenshot(app, named: "oefening-uit-training")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["workout.finish"].waitForExistence(timeout: 5), "The workout is gone after looking at the exercise")
    }

    @MainActor
    func testDuringAWorkoutAtTheLargestTextSize() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let program = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Full body 3×")).firstMatch
        reveal(program, in: app.collectionViews["training.list"], app)
        program.tap()
        let start = app.buttons["training.start.0"]
        XCTAssertTrue(app.collectionViews["program.list"].waitForExistence(timeout: 5))
        reveal(start, in: app.collectionViews["program.list"], app)
        start.tap()
        let explain = app.buttons["workout.exercise.\(backSquat)"]
        XCTAssertTrue(explain.waitForExistence(timeout: 10), "The exercise in the workout cannot be opened")
        keepScreenshot(app, named: "oefening-training-grootste-tekst")
    }
}
