import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
@Suite struct ProfileRecordTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    func makeProfile(weightKg: Double, kcal: Int) -> UserProfile {
        let body = BodyProfile(
            birthDate: BirthDateCalendar.date(from: "1996-01-10")!,
            sex: .male, heightCm: 180, weightKg: weightKg, activityLevel: .moderate, goal: .maintain
        )
        let profile = UserProfile(
            id: UUID(), healthConsentAt: Date(timeIntervalSince1970: 1_800_000_000), healthConsentVersion: 1,
            body: body, targets: NutritionTargets(kcal: kcal, proteinG: 128, carbsG: 389, fatG: 77),
            targetsAreManual: false, updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        context.insert(profile)
        return profile
    }

    @Test func encodesSnakeCaseKeys() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ProfileRecord(makeProfile(weightKg: 80, kcal: 2760)))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "id", "health_consent_at", "health_consent_version", "birth_date", "sex", "height_cm", "weight_kg",
            "activity_level", "goal", "kcal_target", "protein_target_g", "carbs_target_g", "fat_target_g",
            "targets_are_manual", "updated_at",
        ])
        #expect(object["birth_date"] as? String == "1996-01-10")
        #expect(object["activity_level"] as? String == "moderate")
    }

    @Test func decodesServerRowWithSyncedAt() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","health_consent_at":"2026-11-18T12:00:00Z","health_consent_version":1,
         "birth_date":"1996-01-10","sex":"female","height_cm":165.0,"weight_kg":65.5,"activity_level":"very_active",
         "goal":"build_muscle","kcal_target":2000,"protein_target_g":118,"carbs_target_g":250,"fat_target_g":56,
         "targets_are_manual":true,"updated_at":"2026-11-18T12:00:00Z","synced_at":"2026-11-18T12:00:01Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ProfileRecord.self, from: Data(json.utf8))
        #expect(record.weightKg == 65.5)
        #expect(record.activityLevel == "very_active")
        #expect(record.syncedAt != nil)
    }

    @Test func roundTripsThroughUserProfile() {
        let source = makeProfile(weightKg: 80, kcal: 2760)
        let target = makeProfile(weightKg: 95, kcal: 3100)
        target.needsPush = true
        ProfileRecord(source).apply(to: target)
        #expect(target.bodyProfile == source.bodyProfile)
        #expect(target.targets == source.targets)
        #expect(target.healthConsentAt == source.healthConsentAt)
        #expect(target.healthConsentVersion == source.healthConsentVersion)
        #expect(target.targetsAreManual == source.targetsAreManual)
        #expect(target.updatedAt == source.updatedAt)
        #expect(target.needsPush == false)
    }

    @Test func newProfileNeedsPush() {
        #expect(makeProfile(weightKg: 80, kcal: 2760).needsPush)
    }
}
