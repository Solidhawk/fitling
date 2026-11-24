import Foundation
import FitlingCore

/// One request from the web app, `{"fn": name, "input": {...}}`, answered with JSON. Every failure is
/// `{"error": description}`: the web app shows it, and WebAssembly never traps on bad input.
public func handle(_ request: Data) -> Data {
    do {
        let call = try JSONDecoder().decode(Call.self, from: request)
        switch call.fn {
        case "dailyPlan":
            return try encode(dailyPlan(try JSONDecoder().decode(Envelope<DailyPlanInput>.self, from: request).input))
        default:
            return failure("unknown function \(call.fn)")
        }
    } catch let error as CallError {
        return failure(error.description)
    } catch {
        return failure(String(describing: error))
    }
}

struct Call: Decodable {
    let fn: String
}

struct Envelope<Input: Decodable>: Decodable {
    let input: Input
}

struct CallError: Error {
    let description: String
}

struct DailyPlanInput: Decodable {
    /// Days as Postgres writes them: "2026-11-18".
    let birthDay: String
    let sex: Sex
    let heightCm: Double
    let weightKg: Double
    let activityLevel: ActivityLevel
    let goal: Goal
    let today: String
}

struct DailyPlanOutput: Encodable {
    let bmr: Double
    let tdee: Double
    let targets: NutritionTargets
    let floorApplied: Bool
    let warnings: [String]
}

func dailyPlan(_ input: DailyPlanInput) throws -> DailyPlanOutput {
    guard let birthDay = Day(isoString: input.birthDay) else { throw CallError(description: "invalid birthDay \(input.birthDay)") }
    guard let today = Day(isoString: input.today) else { throw CallError(description: "invalid today \(input.today)") }
    let profile = BodyProfile(birthDay: birthDay, sex: input.sex, heightCm: input.heightCm, weightKg: input.weightKg,
                              activityLevel: input.activityLevel, goal: input.goal)
    let plan = NutritionEngine.plan(for: profile, on: today)
    return DailyPlanOutput(bmr: plan.bmr, tdee: plan.tdee, targets: plan.targets, floorApplied: plan.floorApplied,
                           warnings: plan.warnings.map(\.rawValue).sorted())
}

private func encode<Output: Encodable>(_ output: Output) throws -> Data {
    try JSONEncoder().encode(output)
}

private func failure(_ description: String) -> Data {
    (try? JSONEncoder().encode(["error": description])) ?? Data(#"{"error":"unknown"}"#.utf8)
}
