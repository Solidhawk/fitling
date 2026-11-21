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
    }

    @MainActor
    private func shot(_ name: String) {
        count += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "rondleiding-%02d-%@", count, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until the element is on screen. A list makes its rows only when they come near the screen,
    /// so a row far down does not exist until the list has scrolled towards it.
    @MainActor
    private func reveal(_ element: XCUIElement) -> Bool {
        var swipes = 0
        if !element.waitForExistence(timeout: 3) {
            while !element.exists && swipes < 15 {
                app.swipeUp(velocity: .fast)
                swipes += 1
            }
        }
        while element.exists && !element.isHittable && swipes < 15 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Scrolls to the element and taps it; notes the step when it is not there.
    @MainActor
    @discardableResult
    private func tap(_ element: XCUIElement, _ step: String) -> Bool {
        guard reveal(element) else {
            skipped.append(step)
            return false
        }
        element.tap()
        return true
    }

    /// Turns a switch on; a tap on the row does not always reach the switch itself.
    @MainActor
    private func switchOn(_ name: String) {
        let toggle = app.switches[name]
        guard tap(toggle, "schakelaar \(name)") else { return }
        if toggle.value as? String == "0" { toggle.switches.firstMatch.tap() }
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
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing-with-profile", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
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
            if tap(app.buttons["menu.shopping"], "boodschappen") {
                sleep(1)
                shot("boodschappen-leeg")
                if tap(app.buttons["shopping.fromMenu"], "uit het menu") {
                    sleep(1)
                    app.swipeDown(velocity: .fast)
                    shot("boodschappen")
                }
                // The test supermarkets have offers on tomatoes and onions, which the menu needs.
                if tap(button(containing: "Mijn supermarkten"), "supermarkten") {
                    sleep(1)
                    switchOn("Testmarkt")
                    switchOn("Proefsuper")
                    sleep(1)
                    shot("supermarkten")
                    closeSheet()
                    sleep(1)
                    if reveal(button(containing: "Mijn supermarkten")) {
                        app.swipeUp(velocity: .slow)
                        shot("aanbiedingen")
                    } else {
                        skipped.append("aanbiedingen")
                    }
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
            // A SwiftUI Menu is not an ordinary button to XCUITest; it is found by its label.
            let adjust = app.navigationBars.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR identifier == %@", "Aanpassen", "profile.adjust")).firstMatch
            if tap(adjust, "aanpassen-menu"), tap(button(containing: "Profiel bewerken"), "profiel bewerken") {
                sleep(1)
                shot("profiel-bewerken")
                closeSheet()
            }
            if tap(adjust, "aanpassen-menu"), tap(button(containing: "Doelen aanpassen"), "doelen aanpassen") {
                sleep(1)
                shot("doelen-aanpassen")
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
