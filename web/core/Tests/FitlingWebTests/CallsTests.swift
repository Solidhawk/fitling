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

    @Test func unknownFunctionIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data(#"{"fn":"nope","input":{}}"#.utf8)))
        #expect(failure.error == "unknown function nope")
    }

    @Test func brokenJSONIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data("{".utf8)))
        #expect(!failure.error.isEmpty)
    }
}
