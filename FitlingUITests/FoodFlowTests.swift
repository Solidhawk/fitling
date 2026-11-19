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

    /// Rows further down a list are only created once they scroll into view. Several lists can
    /// be on screen (the day under the log sheet), so the one to swipe is named.
    @MainActor
    private func reveal(_ element: XCUIElement, inList list: String, _ app: XCUIApplication) {
        let collection = app.collectionViews[list]
        XCTAssertTrue(collection.waitForExistence(timeout: 10), "No list \(list)")
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 10 {
            collection.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    @MainActor
    private func logScannedProduct(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "\(prefix)-1-vandaag-leeg")

        let addLunch = app.buttons["day.add.lunch"]
        reveal(addLunch, inList: "day.list", app)
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

        XCTAssertTrue(app.collectionViews["portion.form"].waitForExistence(timeout: 10))
        keepScreenshot(app, named: "\(prefix)-4-portie")
        let save = app.buttons["portion.save"]
        reveal(save, inList: "portion.form", app)
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Saving closes the log sheet; the entry is then on the day itself.
        XCTAssertTrue(app.collectionViews["portion.form"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 5))
        let entry = app.collectionViews["day.list"].staticTexts["Double Caramel"]
        reveal(entry, inList: "day.list", app)
        keepScreenshot(app, named: "\(prefix)-5-vandaag-gelogd")
    }

    @MainActor
    func testLogAScannedProduct() {
        let app = launch()
        logScannedProduct(app, prefix: "voeding-licht")

        app.collectionViews["day.list"].swipeDown(velocity: .fast)
        let water = app.buttons["water.add"]
        reveal(water, inList: "day.list", app)
        water.tap()
        water.tap()
        XCTAssertTrue(app.staticTexts["500 ml"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "voeding-licht-6-water")

        // The partner sees the log straight away: today's logging XP is ticked.
        app.tabBars.buttons["Partner"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["partner.hero"].waitForExistence(timeout: 5))
        keepScreenshot(app, named: "voeding-licht-7-partner")
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
