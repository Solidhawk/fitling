import XCTest

final class LaunchTests: XCTestCase {
    /// The database with every model must open as a real file on a device, not only in memory.
    /// When it cannot, the app shows the configuration error, which is the only text there is.
    @MainActor
    func testAppStartsWithTheLocalDatabase() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertEqual(app.staticTexts.count, 0)
    }
}
