import XCTest

final class LaunchTests: XCTestCase {
    /// The database with every model must open as a real file, as on a device; when it cannot,
    /// the app shows the configuration error. The fake server stands in for Supabase: the CI has
    /// no Supabase settings.
    @MainActor
    func testAppStartsWithTheLocalDatabase() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-signed-out", "--ui-testing-on-disk"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.email"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["error.configuration"].exists)
    }

    @MainActor
    func testSignedOutLaunchShowsWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-signed-out"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.google"].exists)
    }
}
