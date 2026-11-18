import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testSignedOutLaunchShowsWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-signed-out"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.google"].exists)
    }
}
