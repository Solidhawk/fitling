import Foundation
import SwiftData
import FitlingCore

extension FitlingSchemaV1 {
    /// One per user. Only what must survive is stored; condition, mood and growth are worked
    /// out by `CreatureEngine` from the logs.
    @Model
    final class Creature {
        @Attribute(.unique) var userID: UUID
        var species: String
        var name: String
        var colorIndex: Int
        var tone: String
        var createdOn: String
        var bodyShape: Double
        var xp: Int
        var lastProcessedOn: String?
        var offTargetDays: Int
        var equippedItems: [String]
        var updatedAt: Date
        var needsPush: Bool

        init(userID: UUID, name: String, state: CreatureState, updatedAt: Date) {
            self.userID = userID
            self.name = name
            self.species = state.species.rawValue
            self.colorIndex = state.colorIndex
            self.tone = state.tone.rawValue
            self.createdOn = state.createdOn.isoString
            self.bodyShape = state.bodyShape
            self.xp = state.xp
            self.lastProcessedOn = state.lastProcessedDay?.isoString
            self.offTargetDays = state.offTargetDays
            self.equippedItems = []
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }
}

extension Creature {
    /// Nil when the stored values are not ones this app version knows.
    var state: CreatureState? {
        guard let species = Species(rawValue: species), let tone = MessageTone(rawValue: tone),
              let createdOn = Day(isoString: createdOn) else { return nil }
        return CreatureState(
            species: species, colorIndex: colorIndex, tone: tone, createdOn: createdOn, bodyShape: bodyShape,
            xp: xp, lastProcessedDay: lastProcessedOn.flatMap(Day.init(isoString:)), offTargetDays: offTargetDays
        )
    }

    /// Takes over what the engine changes. Species, colour and tone are the user's choices and
    /// are set directly.
    func apply(_ state: CreatureState, at date: Date) {
        bodyShape = state.bodyShape
        xp = state.xp
        lastProcessedOn = state.lastProcessedDay?.isoString
        offTargetDays = state.offTargetDays
        updatedAt = date
        needsPush = true
    }
}
