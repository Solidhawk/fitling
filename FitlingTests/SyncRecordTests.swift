import Foundation
import Supabase
import Testing
import FitlingCore
@testable import Fitling

/// The records as they go over the line, with the encoder and decoder the Supabase library uses.
@Suite struct SyncRecordTests {
    let id = UUID(uuidString: "0B0E7E7C-6F0A-4E0D-9C39-2A8B2D0A6F11")!
    let userID = UUID(uuidString: "5D1C2B3A-4F5E-4A6B-8C7D-9E0F1A2B3C4D")!
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    func sent(_ record: some Encodable) throws -> [String: Any] {
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(record)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func profile(postalCode: String?) -> ProfileRecord {
        ProfileRecord(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, birthDate: Day(ordinal: 9505), sex: "female", heightCm: 165.5,
            weightKg: 65.2, activityLevel: "very_active", goal: "build_muscle", kcalTarget: 2400, proteinTargetG: 117, carbsTargetG: 320,
            fatTargetG: 67, targetsAreManual: false, countsWorkoutEnergy: true, postalCode: postalCode, updatedAt: now, syncedAt: now
        )
    }

    func period(deletedAt: Date?) -> TargetPeriodRecord {
        TargetPeriodRecord(
            id: id, userID: userID, effectiveOn: Day(ordinal: 20775), kcalTarget: 2000, proteinTargetG: 150, carbsTargetG: 200,
            fatTargetG: 60, updatedAt: now, deletedAt: deletedAt, syncedAt: now
        )
    }

    @Test func aProfileIsSentWithTheColumnNamesOfTheTable() throws {
        let row = try sent(profile(postalCode: "3511 AB"))
        #expect(Set(row.keys) == [
            "id", "health_consent_at", "health_consent_version", "birth_date", "sex", "height_cm", "weight_kg", "activity_level", "goal",
            "kcal_target", "protein_target_g", "carbs_target_g", "fat_target_g", "targets_are_manual", "counts_workout_energy",
            "postal_code", "updated_at",
        ])
        #expect(row["birth_date"] as? String == "1996-01-10")
        #expect(row["postal_code"] as? String == "3511 AB")
        #expect(row["updated_at"] is String)
    }

    @Test func aTargetPeriodIsSentWithTheColumnNamesOfTheTable() throws {
        let row = try sent(period(deletedAt: now))
        #expect(Set(row.keys) == [
            "id", "user_id", "effective_on", "kcal_target", "protein_target_g", "carbs_target_g", "fat_target_g", "updated_at", "deleted_at",
        ])
        #expect(row["effective_on"] as? String == "2026-11-18")
        #expect(row["deleted_at"] is String)
    }

    @Test func syncedAtIsNeverSent() throws {
        #expect(try sent(profile(postalCode: nil))["synced_at"] == nil)
        #expect(try sent(period(deletedAt: nil))["synced_at"] == nil)
    }

    /// A column that is left out of the request keeps its old value on the server.
    @Test func anEmptyValueIsSentAsNull() throws {
        #expect(try sent(profile(postalCode: nil))["postal_code"] is NSNull)
        #expect(try sent(period(deletedAt: nil))["deleted_at"] is NSNull)
    }

    @Test func aTargetPeriodIsReadFromWhatTheServerSends() throws {
        let json = """
        [{"id":"0b0e7e7c-6f0a-4e0d-9c39-2a8b2d0a6f11","user_id":"5d1c2b3a-4f5e-4a6b-8c7d-9e0f1a2b3c4d","effective_on":"2026-11-18",
        "kcal_target":2000,"protein_target_g":150,"carbs_target_g":200,"fat_target_g":60,
        "updated_at":"2026-11-18T10:00:00+00:00","deleted_at":null,"synced_at":"2026-11-18T10:00:01.123456+00:00"}]
        """
        let records = try PostgrestClient.Configuration.jsonDecoder.decode([TargetPeriodRecord].self, from: Data(json.utf8))
        let record = try #require(records.first)
        #expect(record.id == id)
        #expect(record.userID == userID)
        #expect(record.effectiveOn == Day(year: 2026, month: 11, day: 18))
        #expect(record.kcalTarget == 2000)
        #expect(record.updatedAt == Date(timeIntervalSince1970: 1_794_996_000))
        #expect(record.deletedAt == nil)
        let syncedAt = try #require(record.syncedAt)
        #expect(abs(syncedAt.timeIntervalSince1970 - 1_794_996_001.123) < 0.001)
    }

    @Test func aProfileIsReadFromWhatTheServerSends() throws {
        let json = """
        [{"id":"5d1c2b3a-4f5e-4a6b-8c7d-9e0f1a2b3c4d","health_consent_at":"2026-11-18T10:00:00+00:00","health_consent_version":1,
        "birth_date":"1996-01-10","sex":"female","height_cm":165.5,"weight_kg":65.2,"activity_level":"very_active","goal":"build_muscle",
        "kcal_target":2400,"protein_target_g":117,"carbs_target_g":320,"fat_target_g":67,"targets_are_manual":false,
        "counts_workout_energy":true,"postal_code":null,"created_at":"2026-11-18T10:00:00+00:00",
        "updated_at":"2026-11-18T10:00:00+00:00","synced_at":"2026-11-18T10:00:01.5+00:00"}]
        """
        let records = try PostgrestClient.Configuration.jsonDecoder.decode([ProfileRecord].self, from: Data(json.utf8))
        let record = try #require(records.first)
        #expect(record.id == userID)
        #expect(record.birthDate == Day(ordinal: 9505))
        #expect(record.heightCm == 165.5)
        #expect(record.weightKg == 65.2)
        #expect(record.postalCode == nil)
        #expect(record.countsWorkoutEnergy)
        let syncedAt = try #require(record.syncedAt)
        #expect(abs(syncedAt.timeIntervalSince1970 - 1_794_996_001.5) < 0.001)
    }
}
