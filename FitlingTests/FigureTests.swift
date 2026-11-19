import CoreGraphics
import SwiftUI
import Testing
import FitlingCore
@testable import Fitling

/// The partners are drawn from flat parts. The catalog shows them side by side, so they share one
/// drawing space and stand on one baseline; light and shadow only ever fall on the body.
struct FigureTests {
    @Test(arguments: Species.allCases)
    func everyPartnerHasExactlyOneBody(_ species: Species) {
        #expect(species.parts.filter { $0.role == .body }.count == 1)
    }

    @Test(arguments: Species.allCases)
    func shadingIsDrawnAfterTheBodyItFallsOn(_ species: Species) {
        let parts = species.parts
        let body = parts.firstIndex { $0.role == .body }
        let shading = parts.indices.filter { parts[$0].role == .shading }
        #expect(!shading.isEmpty)
        #expect(shading.allSatisfy { index in body.map { index > $0 } ?? false })
    }

    @Test(arguments: Species.allCases)
    func partnersStayInsideTheirDrawingSpace(_ species: Species) {
        let parts = species.parts
        let body = parts.first { $0.role == .body }?.path.boundingRect ?? .null
        // Shading is clipped to the body, so only the part inside the body is drawn.
        let bounds = parts
            .map { $0.role == .shading ? $0.path.boundingRect.intersection(body) : $0.path.boundingRect }
            .reduce(CGRect.null) { $0.union($1) }
        #expect(!bounds.isNull)
        #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 100 && bounds.maxY <= 100)
        #expect(FigurePart.groundShadow.maxY <= 100)
    }

    @Test(arguments: Species.allCases)
    func partnersStandOnTheSameBaseline(_ species: Species) {
        let outline = species.parts
            .filter { $0.role == .silhouette || $0.role == .body }
            .map(\.path.boundingRect)
            .reduce(CGRect.null) { $0.union($1) }
        #expect(abs(outline.maxY - FigurePart.baseline) < 0.5)
    }
}

/// Every look the partner can have: its moods, shapes, growth, colours and what it wears.
struct PartnerLookTests {
    static let extremes: [PartnerLook] = CreatureMood.allCases.flatMap { mood in
        [0.0, 1.0].flatMap { shape in
            [0, 4].map { stage in
                PartnerLook(colorIndex: 4, mood: mood, bodyShape: shape, growthStage: stage, trainedRecently: true, items: CreatureItem.allCases)
            }
        }
    }

    @Test(arguments: Species.allCases)
    func everyLookStaysInsideTheDrawingSpace(_ species: Species) {
        for look in Self.extremes {
            let parts = species.parts(for: look)
            let body = parts.first { $0.role == .body }?.path.boundingRect ?? .null
            let bounds = parts
                .map { $0.role == .shading ? $0.path.boundingRect.intersection(body) : $0.path.boundingRect }
                .filter { !$0.isNull }
                .reduce(CGRect.null) { $0.union($1) }
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 100 && bounds.maxY <= 100, "\(species) \(look)")
            #expect(parts.filter { $0.role == .body }.count == 1)
        }
    }

    @Test(arguments: Species.allCases)
    func aRoundPartnerIsWiderThanALeanOne(_ species: Species) {
        func bodyWidth(_ shape: Double) -> CGFloat {
            species.parts(for: PartnerLook(bodyShape: shape)).first { $0.role == .body }?.path.boundingRect.width ?? 0
        }
        #expect(bodyWidth(0) < bodyWidth(CreatureEngine.startShape))
        #expect(bodyWidth(CreatureEngine.startShape) < bodyWidth(1))
    }

    @Test(arguments: Species.allCases)
    func everyMoodHasItsOwnFace(_ species: Species) {
        let faces = CreatureMood.allCases.map { mood in
            species.parts(for: PartnerLook(mood: mood)).filter { $0.role == .detail }.map { "\($0.path.boundingRect)" }
        }
        #expect(Set(faces).count == CreatureMood.allCases.count)
    }

    @Test(arguments: Species.allCases)
    func everyAccessoryIsDrawn(_ species: Species) {
        let bare = species.parts(for: PartnerLook()).count
        for item in CreatureItem.allCases {
            #expect(species.parts(for: PartnerLook(items: [item])).count > bare, "\(item)")
        }
    }

    @Test(arguments: Species.allCases)
    func theOldestPartnersHaveTheMostToShow(_ species: Species) {
        let counts = (0...4).map { species.parts(for: PartnerLook(growthStage: $0)).count }
        #expect(counts.first! < counts.last!)
    }

    @Test(arguments: Species.allCases)
    func everyColourHasItsOwnBody(_ species: Species) {
        #expect(species.palettes.count == CreatureEngine.baseColorCount + CreatureEngine.colorUnlockLevels.count)
        #expect(Set(species.palettes.map { "\($0.body)" }).count == species.palettes.count)
    }

    @Test func aPartnerAtRestDoesNotMove() {
        #expect(PartnerMotion.still == PartnerMotion(lift: 0, squash: 1))
        let lively = (0..<20).map { PartnerMotion(at: Double($0) * 0.1, energy: 1, asleep: false).lift }
        let sleepy = (0..<20).map { PartnerMotion(at: Double($0) * 0.1, energy: 0.1, asleep: false).lift }
        #expect(lively.max()! > sleepy.max()!)
        #expect((0..<20).allSatisfy { PartnerMotion(at: Double($0) * 0.1, energy: 1, asleep: true).lift == 0 })
    }
}
