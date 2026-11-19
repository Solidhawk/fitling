import XCTest

/// Logging food on the fake server: the app starts with a finished profile and the fake
/// `lookup-product` knows one barcode (8712100849084, a real Open Food Facts product).
final class FoodFlowTests: XCTestCase {
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

    /// Rows further down the day are only created once they scroll into view.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 10 {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    @MainActor
    private func logScannedProduct(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "\(prefix)-1-vandaag-leeg")

        let addLunch = app.buttons["day.add.lunch"]
        reveal(addLunch, in: app)
        addLunch.tap()

        let scan = app.buttons["log.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        keepScreenshot(app, named: "\(prefix)-2-loggen")
        scan.tap()

        // The simulator has no camera, so the barcode is typed in.
        let field = app.textFields["scan.manual"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("8712100849084")
        keepScreenshot(app, named: "\(prefix)-3-scannen")
        app.buttons["scan.manual.submit"].tap()

        let save = app.buttons["portion.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        keepScreenshot(app, named: "\(prefix)-4-portie")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let entry = app.staticTexts["Double Caramel"]
        reveal(entry, in: app)
        keepScreenshot(app, named: "\(prefix)-5-vandaag-gelogd")
    }

    @MainActor
    func testLogAScannedProduct() {
        let app = launch()
        logScannedProduct(app, prefix: "voeding-licht")

        app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        let water = app.buttons["water.add"]
        reveal(water, in: app)
        water.tap()
        water.tap()
        XCTAssertTrue(app.staticTexts["500 ml"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "voeding-licht-6-water")
    }

    @MainActor
    func testLogAScannedProductInDarkMode() {
        logScannedProduct(launch(["--ui-testing-dark"]), prefix: "voeding-donker")
    }

    @MainActor
    func testLogAScannedProductAtTheLargestTextSize() {
        logScannedProduct(
            launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
            prefix: "voeding-grootste-tekst"
        )
    }
}
