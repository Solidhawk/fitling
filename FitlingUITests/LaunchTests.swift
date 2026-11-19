import XCTest

final class LaunchTests: XCTestCase {
    /// Without test arguments the app opens its real database file and its real configuration.
    /// Signed out, that ends on the welcome screen, not on the configuration error.
    @MainActor
    func testAppStartsWithTheLocalDatabase() {
        let app = XCUIApplication()
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
