import Foundation
import SwiftData
import FitlingCore

/// The row of `creatures`: one per user, keyed by the user.
struct CreatureRecord: SyncRecord, Equatable {
    var userID: UUID
    var species: String
    var name: String
    var colorIndex: Int
    var tone: String
    var createdOn: Day
    var bodyShape: Double
    var xp: Int
    var lastProcessedOn: Day?
    var offTargetDays: Int
    var equippedItems: [String]
    var updatedAt: Date
    var syncedAt: Date?

    var id: UUID { userID }
    /// A partner is never deleted on its own; it goes with the account.
    var deletedAt: Date? { nil }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case species
        case name
        case colorIndex = "color_index"
        case tone
        case createdOn = "created_on"
        case bodyShape = "body_shape"
        case xp
        case lastProcessedOn = "last_processed_on"
        case offTargetDays = "off_target_days"
        case equippedItems = "equipped_items"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    /// `synced_at` belongs to the server and is never sent; an empty value goes as null.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(species, forKey: .species)
        try container.encode(name, forKey: .name)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(tone, forKey: .tone)
        try container.encode(createdOn, forKey: .createdOn)
        try container.encode(bodyShape, forKey: .bodyShape)
        try container.encode(xp, forKey: .xp)
        try container.encode(lastProcessedOn, forKey: .lastProcessedOn)
        try container.encode(offTargetDays, forKey: .offTargetDays)
        try container.encode(equippedItems, forKey: .equippedItems)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension Creature: SyncableModel {
    static var tableName: String { "creatures" }
    static var keyColumn: String { "user_id" }

    static var pending: FetchDescriptor<Creature> {
        FetchDescriptor(predicate: #Predicate<Creature> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<Creature> {
        FetchDescriptor(predicate: #Predicate<Creature> { ids.contains($0.userID) })
    }

    static func make(from record: CreatureRecord) -> Creature {
        // The typed state only gets the row started; `apply` then stores the server's own text,
        // including a species or tone a newer app version may have written.
        let state = CreatureState(
            species: Species(rawValue: record.species) ?? .bumblebee, colorIndex: record.colorIndex,
            tone: MessageTone(rawValue: record.tone) ?? .sweet, createdOn: record.createdOn
        )
        let creature = Creature(userID: record.userID, name: record.name, state: state, updatedAt: record.updatedAt)
        creature.apply(record)
        return creature
    }

    var syncID: UUID { userID }
    var deletedAt: Date? { nil }

    var record: CreatureRecord {
        CreatureRecord(
            userID: userID, species: species, name: name, colorIndex: colorIndex, tone: tone,
            createdOn: Day(isoString: createdOn) ?? Day(ordinal: 0), bodyShape: bodyShape, xp: xp,
            lastProcessedOn: lastProcessedOn.flatMap(Day.init(isoString:)), offTargetDays: offTargetDays,
            equippedItems: equippedItems, updatedAt: updatedAt, syncedAt: nil
        )
    }

    func apply(_ record: CreatureRecord) {
        species = record.species
        name = record.name
        colorIndex = record.colorIndex
        tone = record.tone
        createdOn = record.createdOn.isoString
        bodyShape = record.bodyShape
        xp = record.xp
        lastProcessedOn = record.lastProcessedOn?.isoString
        offTargetDays = record.offTargetDays
        equippedItems = record.equippedItems
        updatedAt = record.updatedAt
        needsPush = false
    }
}
