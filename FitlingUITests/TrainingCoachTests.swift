import XCTest

/// The coach on the Training tab after a few weeks of made-up workouts: one exercise that can go
/// heavier and one that has stalled, with another exercise for the same muscle to try.
final class TrainingCoachTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func coach(_ extra: [String], named name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-workout-history", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"] + extra
        app.launch()

        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 5))

        let list = app.collectionViews["training.list"]
        let heavier = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "training.coach.heavier.")).firstMatch
        let switchTo = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "training.coach.switch.")).firstMatch
        XCTAssertTrue(heavier.waitForExistence(timeout: 5), "No note to go heavier")
        // At the largest text the notes can sit below the screen.
        var swipes = 0
        while !(switchTo.exists && switchTo.isHittable) && swipes < 8 {
            list.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(switchTo.exists, "No note to switch exercises")
        XCTAssertTrue(switchTo.label.contains("Squat met halter"), switchTo.label)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCoach() {
        coach([], named: "coach-licht")
    }

    @MainActor
    func testCoachInDarkMode() {
        coach(["--ui-testing-dark"], named: "coach-donker")
    }

    @MainActor
    func testCoachAtTheLargestTextSize() {
        coach(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], named: "coach-grootste-tekst")
    }
}
