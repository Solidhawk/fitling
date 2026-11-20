import XCTest

/// A walk past every page of the app, with a screenshot of each, so the user can review the whole
/// app page by page. It starts with a finished profile and a partner. A step whose button cannot be
/// found is noted in an attachment and skipped, so one missing control does not end the walk; the
/// flows that check behaviour are the other UI tests.
final class AppTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var count = 0
    private var skipped: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
    }

    @MainActor
    private func shot(_ name: String) {
        count += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "rondleiding-%02d-%@", count, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until the element is on screen and taps it; notes the step when it is not there.
    @MainActor
    @discardableResult
    private func tap(_ element: XCUIElement, _ step: String) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            skipped.append(step)
            return false
        }
        var swipes = 0
        while !element.isHittable && swipes < 8 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        guard element.isHittable else {
            skipped.append(step)
            return false
        }
        element.tap()
        return true
    }

    @MainActor
    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func back() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists { backButton.tap() }
    }

    /// Closes a sheet with its cancel button, or by pulling it down.
    @MainActor
    private func closeSheet() {
        for label in ["Annuleren", "Klaar", "OK", "Sluiten"] where app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        app.swipeDown(velocity: .fast)
    }

    @MainActor
    private func openTab(_ name: String) -> Bool {
        let tab = app.tabBars.buttons[name]
        guard tab.waitForExistence(timeout: 10) else {
            skipped.append("tab \(name)")
            return false
        }
        tab.tap()
        return true
    }

    @MainActor
    func testTourOfEveryPage() {
        app.launch()

        // Vandaag
        if openTab("Vandaag") {
            _ = app.navigationBars["Vandaag"].waitForExistence(timeout: 10)
            shot("vandaag")
            if tap(app.buttons["day.add.breakfast"], "ontbijt toevoegen") {
                _ = app.searchFields.firstMatch.waitForExistence(timeout: 5)
                shot("loggen")
                if tap(button(containing: "Eigen product"), "eigen product") {
                    sleep(1)
                    shot("eigen-product")
                    closeSheet()
                }
                closeSheet()
            }
        }

        // Training
        if openTab("Training") {
            _ = app.navigationBars["Training"].waitForExistence(timeout: 5)
            shot("training")
            if tap(button(containing: "Full body 3×"), "schema") {
                sleep(1)
                shot("schema")
                back()
            }
            for (label, name) in [("Per oefening", "per-oefening"), ("Volume per spiergroep", "volume"), ("Lichaam", "lichaam"), ("Voortgangsfoto's", "voortgangsfotos")] {
                if tap(button(containing: label), name) {
                    sleep(1)
                    shot(name)
                    back()
                }
            }
            if tap(button(containing: "Eigen schema maken"), "eigen schema") {
                sleep(1)
                shot("eigen-schema")
                closeSheet()
            }
        }

        // Menu, recepten en boodschappen
        if openTab("Menu") {
            _ = app.navigationBars["Menu"].waitForExistence(timeout: 5)
            shot("menu-leeg")
            if tap(app.buttons["menu.generate.first"], "weekmenu maken") {
                sleep(2)
                shot("weekmenu")
            }
            if tap(button(containing: "Voorkeuren"), "voorkeuren") {
                sleep(1)
                shot("voorkeuren")
                closeSheet()
            }
            if tap(button(containing: "Recepten"), "recepten") {
                sleep(1)
                shot("recepten")
                if tap(app.collectionViews.cells.element(boundBy: 0), "recept") {
                    sleep(1)
                    shot("recept")
                    back()
                }
                back()
            }
            if tap(button(containing: "Boodschappen"), "boodschappen") {
                sleep(1)
                shot("boodschappen")
                if tap(button(containing: "Mijn supermarkten"), "supermarkten") {
                    sleep(1)
                    shot("supermarkten")
                    closeSheet()
                }
                back()
            }
        }

        // Partner
        if openTab("Partner") {
            _ = app.navigationBars["Partner"].waitForExistence(timeout: 5)
            shot("partner")
            app.swipeUp(velocity: .slow)
            shot("partner-onder")
            app.swipeDown(velocity: .fast)
            if tap(app.navigationBars.buttons["Aanpassen"], "partner aanpassen") {
                sleep(1)
                shot("partner-aanpassen")
                closeSheet()
            }
        }

        // Dagdoel, profiel en account
        if openTab("Dagdoel") {
            _ = app.navigationBars["Dagdoel"].waitForExistence(timeout: 5)
            shot("dagdoel")
            if tap(app.buttons["profile.adjust"], "aanpassen-menu"), tap(button(containing: "Profiel bewerken"), "profiel bewerken") {
                sleep(1)
                shot("profiel-bewerken")
                closeSheet()
            }
            if tap(button(containing: "Account"), "account") {
                sleep(1)
                shot("account")
                if tap(button(containing: "Over Fitling"), "over") {
                    sleep(1)
                    shot("over")
                    back()
                }
                if tap(button(containing: "Gegevens exporteren"), "exporteren") {
                    sleep(2)
                    shot("exporteren")
                }
            }
        }

        let note = XCTAttachment(string: skipped.isEmpty ? "Alle stappen gelukt." : "Overgeslagen: " + skipped.joined(separator: ", "))
        note.name = "rondleiding-overgeslagen"
        note.lifetime = .keepAlways
        add(note)
    }
}
