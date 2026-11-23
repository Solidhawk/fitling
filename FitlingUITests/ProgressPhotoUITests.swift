import XCTest

/// Progress photos: a tap on a tile opens that photo, also beside a landscape photo (UNFORGET S32).
final class ProgressPhotoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testATapBesideALandscapePhotoOpensTheTappedPhoto() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "--ui-testing-progress-photos", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Vandaag"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Training"].tap()
        let photos = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Voortgangsfoto's")).firstMatch
        var swipes = 0
        while !(photos.exists && photos.isHittable) && swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        photos.tap()

        // Newest first: today's portrait photo, then yesterday's landscape one beside it.
        let tiles = app.buttons.matching(identifier: "photos.tile")
        XCTAssertTrue(tiles.element(boundBy: 1).waitForExistence(timeout: 10))
        let portrait = tiles.element(boundBy: 0)
        let date = portrait.label
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "voortgangsfotos-liggend"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Near the right edge of today's tile, where yesterday's photo would reach without the fix.
        portrait.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars[date].waitForExistence(timeout: 5), "Tapped the photo of \(date), another photo opened")
    }
}
