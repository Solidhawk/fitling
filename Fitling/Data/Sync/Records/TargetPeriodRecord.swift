import Foundation
import SwiftData
import FitlingCore

/// A row of `target_history`.
struct TargetPeriodRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var effectiveOn: Day
    var kcalTarget: Int
    var proteinTargetG: Int
    var carbsTargetG: Int
    var fatTargetG: Int
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case effectiveOn = "effective_on"
        case kcalTarget = "kcal_target"
        case proteinTargetG = "protein_target_g"
        case carbsTargetG = "carbs_target_g"
        case fatTargetG = "fat_target_g"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    /// See `ProfileRecord.encode(to:)`: no `synced_at`, and an empty `deleted_at` as null.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(effectiveOn, forKey: .effectiveOn)
        try container.encode(kcalTarget, forKey: .kcalTarget)
        try container.encode(proteinTargetG, forKey: .proteinTargetG)
        try container.encode(carbsTargetG, forKey: .carbsTargetG)
        try container.encode(fatTargetG, forKey: .fatTargetG)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

extension TargetPeriod: SyncableModel {
    static var tableName: String { "target_history" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<TargetPeriod> {
        FetchDescriptor(predicate: #Predicate<TargetPeriod> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<TargetPeriod> {
        FetchDescriptor(predicate: #Predicate<TargetPeriod> { ids.contains($0.id) })
    }

    static func make(from record: TargetPeriodRecord) -> TargetPeriod {
        let period = TargetPeriod(
            id: record.id, userID: record.userID, effectiveOn: record.effectiveOn,
            targets: NutritionTargets(kcal: record.kcalTarget, proteinG: record.proteinTargetG, carbsG: record.carbsTargetG, fatG: record.fatTargetG),
            updatedAt: record.updatedAt
        )
        period.apply(record)
        return period
    }

    var syncID: UUID { id }

    var record: TargetPeriodRecord {
        TargetPeriodRecord(
            id: id, userID: userID, effectiveOn: Day(isoString: effectiveOn) ?? Day(ordinal: 0), kcalTarget: kcalTarget,
            proteinTargetG: proteinTargetG, carbsTargetG: carbsTargetG, fatTargetG: fatTargetG,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: TargetPeriodRecord) {
        userID = record.userID
        effectiveOn = record.effectiveOn.isoString
        kcalTarget = record.kcalTarget
        proteinTargetG = record.proteinTargetG
        carbsTargetG = record.carbsTargetG
        fatTargetG = record.fatTargetG
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
