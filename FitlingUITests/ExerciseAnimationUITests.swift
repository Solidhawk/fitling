import XCTest

/// The animated exercises on their own screen: Training, "Per oefening", the exercise.
final class ExerciseAnimationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openList(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-animated-exercises", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let perExercise = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Per oefening")).firstMatch
        let list = app.collectionViews["training.list"]
        // Wholly inside the list: a row behind the tab bar counts as hittable, but the tap lands on the bar.
        var swipes = 0
        while !(perExercise.exists && perExercise.isHittable && perExercise.frame.maxY < app.tabBars.firstMatch.frame.minY) && swipes < 12 {
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(perExercise.exists, "No link to the exercises")
        perExercise.tap()
        return app
    }

    @MainActor
    private func open(_ name: String, _ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 12 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No row for \(name)")
        row.tap()
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testOneExerciseOfEachKind() {
        let app = openList()
        let exercises = [
            ("Crunch aan de kabel", "crunch"), ("Eenarmig roeien", "roeien"), ("Face pull", "facepull"), ("Goblet squat", "goblet"),
            ("Hangend benen heffen", "benen-heffen"), ("Hip thrust", "hipthrust"), ("Kettlebell swing", "swing"),
            ("Opdrukken op de knieën", "opdrukken"), ("Russische twist", "twist"), ("Squat met halter", "squat"),
            ("Vliegen met dumbbells", "vliegen"), ("Zijliggend been heffen", "zijliggend"),
        ]
        for (name, file) in exercises {
            open(name, app)
            XCTAssertTrue(app.buttons["exercise.animation"].waitForExistence(timeout: 10), "No animation for \(name)")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Everkinetic")).firstMatch.exists)
            keepScreenshot(app, named: "animatie-\(file)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    @MainActor
    func testTheAnimationMovesAndPauses() {
        let app = openList()
        open("Goblet squat", app)
        let animation = app.buttons["exercise.animation"]
        XCTAssertTrue(animation.waitForExistence(timeout: 10))

        // The squat rests for less than a second, so within a few looks the picture has changed.
        let first = animation.screenshot().pngRepresentation
        var moved = false
        for _ in 0..<8 where !moved {
            Thread.sleep(forTimeInterval: 0.4)
            moved = animation.screenshot().pngRepresentation != first
        }
        XCTAssertTrue(moved, "The animation does not move")

        XCTAssertEqual(animation.label, "Animatie pauzeren")
        animation.tap()
        XCTAssertEqual(animation.label, "Animatie afspelen")
        // Let the press fade before comparing.
        Thread.sleep(forTimeInterval: 1)
        let paused = animation.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(animation.screenshot().pngRepresentation, paused, "The animation moves while paused")
        keepScreenshot(app, named: "animatie-gepauzeerd")
    }

    @MainActor
    func testWithReduceMotionTheStartAndEndStandStill() {
        let app = openList(["--ui-testing-reduce-motion"])
        open("Goblet squat", app)
        XCTAssertTrue(app.descendants(matching: .any)["exercise.animation.still"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["exercise.animation"].exists)
        keepScreenshot(app, named: "animatie-minder-beweging")
    }

    @MainActor
    func testInDarkMode() {
        let app = openList(["--ui-testing-dark"])
        open("Hip thrust", app)
        XCTAssertTrue(app.buttons["exercise.animation"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "animatie-donker")
    }

    @MainActor
    func testAtTheLargestTextSize() {
        let app = openList(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open("Goblet squat", app)
        XCTAssertTrue(app.buttons["exercise.animation"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "animatie-grootste-tekst")
    }
}
