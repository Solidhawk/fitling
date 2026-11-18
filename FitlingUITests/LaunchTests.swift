import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["root.loading"].waitForExistence(timeout: 5))
    }
}
