import XCTest

/// Every look of every species, for approving the drawings (TASKS 3.3). The gallery is a debug
/// screen; its order is explained in `PartnerGallery`.
final class PartnerGalleryTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryLookOfEverySpecies() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-partner-gallery", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["gallery"].waitForExistence(timeout: 10))
        for species in [
            "bumblebee", "mole", "frog", "owl", "hedgehog", "snail", "axolotl", "seal",
            "penguin", "turtle", "rabbit", "raccoon", "ladybird", "octopus", "squirrel", "lamb",
        ] {
            let button = app.buttons["gallery.\(species)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            let name = button.label
            button.tap()
            // The name plate follows the tap: a tap that lands on a neighbouring partner shows its name instead.
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 2), "Tapped \(name), the gallery shows another partner")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "partner-galerij-\(species)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
