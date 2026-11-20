import SwiftUI
import Testing
import UIKit
import FitlingCore
@testable import Fitling

/// The partners are stacks of 3D renders: a body, a face per mood, and what they wear. All layers of
/// one species and form come from one camera, so they only line up if every one of them exists.
struct PartnerLayersTests {
    @Test func theStackStartsWithTheBodyAndTheFaceOfTheMood() {
        let layers = PartnerLayers.layers(.owl, look: PartnerLook(mood: .hungry, growthStage: 3))
        #expect(layers.map(\.name) == ["partner-owl-4-body", "partner-owl-4-face-hungry"])
    }

    @Test func itemsGoOnInAFixedOrderAndTheSweatbandLast() {
        let look = PartnerLook(trainedRecently: true, items: [.crown, .backpack, .glasses])
        let names = PartnerLayers.layers(.frog, look: look).dropFirst(2).map(\.name)
        #expect(names == ["partner-frog-1-item-backpack", "partner-frog-1-item-glasses", "partner-frog-1-item-crown", "partner-frog-1-item-sweatband"])
    }

    @Test func onlyTheBodyTakesTheColour() {
        let layers = PartnerLayers.layers(.lamb, look: PartnerLook(colorIndex: 3, items: [.scarf]))
        #expect(layers.map(\.takesColor) == [true, false, false])
    }

    @Test func theCatalogShowsOnlyTheFirstForm() {
        // Later forms stay a surprise: they only appear on the partner once its level reaches them.
        #expect(PartnerLook.catalog.growthStage == 0)
        #expect(PartnerLook().growthStage == 0)
        #expect(PartnerLayers.layers(.owl, look: .catalog).allSatisfy { $0.name.hasPrefix("partner-owl-1-") })
    }

    @Test func everyGrowthStageHasItsOwnForm() {
        #expect((0..<CreatureEngine.growthLevels.count).map(PartnerLayers.form(for:)) == [1, 2, 3, 4, 5, 6])
        #expect(PartnerLayers.form(for: -1) == 1)
        #expect(PartnerLayers.form(for: 9) == 6)
    }

    @Test func everyColourTurnsTheHueByItsOwnAmount() {
        #expect(PartnerLayers.hues.count == CreatureEngine.baseColorCount + CreatureEngine.colorUnlockLevels.count)
        #expect(Set(PartnerLayers.hues).count == PartnerLayers.hues.count)
        #expect(PartnerLayers.hue(for: 0) == .zero)
    }

    @Test func aRoundPartnerIsWiderThanALeanOne() {
        #expect(PartnerLook(bodyShape: 0).width < PartnerLook(bodyShape: CreatureEngine.startShape).width)
        #expect(PartnerLook(bodyShape: CreatureEngine.startShape).width == 1)
        #expect(PartnerLook(bodyShape: 1).width > 1.15)
    }

    @Test(arguments: Species.allCases)
    func everyLayerOfEverySpeciesIsInTheApp(_ species: Species) {
        var missing: [String] = []
        for form in 1...PartnerLayers.formCount {
            let base = PartnerLayers.prefix(species, form: form)
            let names = ["\(base)-body", "\(base)-item-sweatband"]
                + CreatureMood.allCases.map { "\(base)-face-\($0.rawValue)" }
                + CreatureItem.allCases.map { "\(base)-item-\($0.rawValue)" }
            missing += names.filter { UIImage(named: $0) == nil }
        }
        #expect(missing.isEmpty, "\(missing.prefix(5))")
    }

    @Test(arguments: Species.allCases)
    func everyFormKnowsWhereTheHeadIs(_ species: Species) throws {
        for form in 1...PartnerLayers.formCount {
            let anchor = try #require(PartnerAnchor.of(species, form: form), "\(species) \(form)")
            #expect((0...1).contains(anchor.headTop[1]) && anchor.headTop[1] < anchor.headCenter[1])
            #expect(anchor.headRadius > 0 && anchor.headRadius < 0.5)
            #expect(anchor.figure.count == 4 && anchor.figure[0] < anchor.figure[2] && anchor.figure[1] < anchor.figure[3])
        }
    }

    @Test(arguments: Species.allCases)
    func everySpeciesHasItsOwnColours(_ species: Species) {
        #expect(UIColor(named: "PartnerRibbon/\(species.rawValue)") != nil)
        #expect(UIColor(named: "PartnerTint/\(species.rawValue)") != nil)
    }

    @Test func aSmallFigureIsZoomedToItsFormsHeightWithItsFeetOnTheGround() {
        // A form-1 figure: 0.24 of the render high, 0.2 wide, centred a little to the right.
        let framing = PartnerFraming(figure: [0.42, 0.6, 0.62, 0.84], form: 1)
        #expect(abs(framing.scale * 0.24 - PartnerFraming.heights[0]) < 0.001)
        #expect(abs(framing.point(0.52, 0.84).x - 0.5) < 0.001)
        #expect(abs(framing.point(0.52, 0.84).y - PartnerFraming.ground) < 0.001)
    }

    @Test func aWideFigureIsZoomedOnlyAsFarAsItFits() {
        let framing = PartnerFraming(figure: [0.05, 0.1, 0.95, 0.9], form: 6)
        #expect(framing.scale * 0.9 <= PartnerFraming.maxWidth + 0.001)
    }

    @Test func laterFormsFillMoreOfTheFrame() {
        #expect(PartnerFraming.heights.count == PartnerLayers.formCount)
        #expect(zip(PartnerFraming.heights, PartnerFraming.heights.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func aPartnerAtRestDoesNotMove() {
        #expect(PartnerMotion.still == PartnerMotion(lift: 0, squash: 1))
        let lively = (0..<20).map { PartnerMotion(at: Double($0) * 0.1, energy: 1, asleep: false).lift }
        let sleepy = (0..<20).map { PartnerMotion(at: Double($0) * 0.1, energy: 0.1, asleep: false).lift }
        #expect(lively.max()! > sleepy.max()!)
        #expect((0..<20).allSatisfy { PartnerMotion(at: Double($0) * 0.1, energy: 1, asleep: true).lift == 0 })
    }
}
