import Foundation
import Testing
@testable import FitlingWeb

/// The bridge answers with what FitlingCore answers in the app.
@Suite struct CallsTests {
    struct Targets: Decodable, Equatable {
        let kcal: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
    }

    struct Plan: Decodable {
        let bmr: Double
        let tdee: Double
        let targets: Targets
        let floorApplied: Bool
        let warnings: [String]
    }

    struct Failure: Decodable {
        let error: String
    }

    let maintainRequest = #"{"fn":"dailyPlan","input":{"birthDay":"1996-01-10","sex":"male","heightCm":180,"weightKg":80,"activityLevel":"moderate","goal":"maintain","today":"2026-11-18"}}"#

    /// The same profile and values as NutritionEngineTests.maintenanceTargetEqualsTotalExpenditure.
    @Test func dailyPlanMatchesTheApp() throws {
        let plan = try JSONDecoder().decode(Plan.self, from: handle(Data(maintainRequest.utf8)))
        #expect(plan.targets == Targets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        #expect(abs(plan.bmr - 1780) < 0.0001)
        #expect(plan.floorApplied == false)
        #expect(plan.warnings.isEmpty)
    }

    /// An absurd number from a form is an error with a message, never a trap in WebAssembly.
    @Test func absurdNumbersAreAnError() throws {
        let request = maintainRequest.replacingOccurrences(of: #""weightKg":80"#, with: #""weightKg":1e300"#)
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data(request.utf8)))
        #expect(failure.error.contains("weightKg"))
    }

    @Test func unknownFunctionIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data(#"{"fn":"nope","input":{}}"#.utf8)))
        #expect(failure.error == "unknown function nope")
    }

    @Test func brokenJSONIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data("{".utf8)))
        #expect(!failure.error.isEmpty)
    }

    // MARK: - The calls of onboarding, partner setup and Dagdoel (web fase 1)

    func answer(_ fn: String, _ input: String) throws -> [String: Any] {
        let data = handle(Data(#"{"fn":"\#(fn)","input":\#(input)}"#.utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// 5 ft 11 in and 176 lb, as the profile editor converts them.
    @Test func bodyInputConvertsImperialUnits() throws {
        let result = try answer("bodyInput", #"{"usesMetric":false,"fields":{"feet":5,"inches":11,"weight":176}}"#)
        #expect(number(result["heightCm"]) == 180.3)
        #expect(number(result["weightKg"]) == 79.8)
        #expect(result["isValid"] as? Bool == true)
    }

    /// Fields filled from a stored profile give back the stored values, not a rounded conversion.
    @Test func bodyInputKeepsStoredValues() throws {
        let result = try answer("bodyInput", #"{"usesMetric":false,"stored":{"heightCm":180,"weightKg":80}}"#)
        let fields = try #require(result["fields"] as? [String: Any])
        #expect(number(fields["feet"]) == 5)
        #expect(number(fields["inches"]) == 10.9)
        #expect(number(fields["weight"]) == 176.4)
        #expect(number(result["heightCm"]) == 180)
        #expect(number(result["weightKg"]) == 80)
    }

    @Test func birthDayChecksAgeAndAdulthood() throws {
        let adult = try answer("birthDay", #"{"birthDay":"1996-01-10","today":"2026-11-18"}"#)
        #expect(number(adult["age"]) == 30)
        #expect(adult["isAdult"] as? Bool == true)
        #expect(adult["isValid"] as? Bool == true)
        let young = try answer("birthDay", #"{"birthDay":"2010-01-01","today":"2026-11-18"}"#)
        #expect(young["isAdult"] as? Bool == false)
        #expect(young["isValid"] as? Bool == false)
    }

    @Test func macrosAndSharesMatchTheApp() throws {
        let targets = try answer("macros", #"{"kcal":2760,"weightKg":80,"goal":"maintain"}"#)
        #expect(number(targets["proteinG"]) == 128)
        #expect(number(targets["carbsG"]) == 389)
        #expect(number(targets["fatG"]) == 77)
        let shares = try answer("kcalShares", #"{"kcal":2760,"proteinG":128,"carbsG":389,"fatG":77}"#)
        #expect(abs((number(shares["protein"]) ?? 0) - 512.0 / 2760) < 0.0001)
        let warnings = try answer("warnings", #"{"kcal":2760,"bmr":1780,"tdee":2759,"sex":"male"}"#)
        #expect((warnings["warnings"] as? [String]) == [])
        let low = try answer("warnings", #"{"kcal":1000,"bmr":1780,"tdee":2759,"sex":"male"}"#)
        #expect(((low["warnings"] as? [String]) ?? []).contains("below_common_minimum"))
    }

    /// The same rule as TargetPeriodsTests: the newest period on the same day holds.
    @Test func targetsOnDayFollowTheNewestPeriod() throws {
        let result = try answer("targetsOnDay", #"{"day":"2026-11-10","fallback":{"kcal":2000,"proteinG":100,"carbsG":250,"fatG":70},"periods":[{"effectiveOn":"2026-11-10","updatedAtMs":1000,"targets":{"kcal":2200,"proteinG":120,"carbsG":270,"fatG":75}},{"effectiveOn":"2026-11-10","updatedAtMs":2000,"targets":{"kcal":2500,"proteinG":150,"carbsG":300,"fatG":80}}]}"#)
        #expect(number(result["kcal"]) == 2500)
    }

    @Test func aNewPartnerStartsAsTheAppSays() throws {
        let result = try answer("creature", #"{"level":1}"#)
        #expect(number(result["startShape"]) == 0.3)
        #expect(number(result["colorCount"]) == 3)
        #expect(number(result["growthStage"]) == 0)
    }
}
