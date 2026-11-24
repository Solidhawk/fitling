#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

/// One request from the web app, `{"fn": name, "input": {...}}`, answered with JSON. Every failure is
/// `{"error": description}`: the web app shows it, and WebAssembly never traps on bad input.
public func handle(_ request: Data) -> Data {
    do {
        let call = try JSONDecoder().decode(Call.self, from: request)
        switch call.fn {
        case "dailyPlan": return try encode(dailyPlan(try input(request)))
        case "bodyInput": return try encode(bodyInput(try input(request)))
        case "birthDay": return try encode(birthDay(try input(request)))
        case "macros": return try encode(macros(try input(request)))
        case "kcalShares": return try encode(kcalShares(try input(request)))
        case "warnings": return try encode(warnings(try input(request)))
        case "targetsOnDay": return try encode(targetsOnDay(try input(request)))
        case "creature": return try encode(creature(try input(request)))
        case "goalFactors": return try encode(goalFactors())
        case "profileRules": return try encode(profileRules())
        case "searchKey": return try encode(searchKey(try input(request)))
        case "barcode": return try encode(barcode(try input(request)))
        case "recentProducts": return try encode(recentProducts(try input(request)))
        case "portion": return try encode(portion(try input(request)))
        case "logEntry": return try encode(logEntry(try input(request)))
        case "ownProduct": return try encode(ownProduct(try input(request)))
        case "dayTotals": return try encode(dayTotals(try input(request)))
        case "partnerSnapshot": return try encode(partnerSnapshot(try input(request)))
        case "advanceFrom": return try encode(advanceFrom(try input(request)))
        case "partnerAdvance": return try encode(partnerAdvance(try input(request)))
        case "wearing": return try encode(wearing(try input(request)))
        case "localizedText": return try encode(localizedText(try input(request)))
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

func input<Input: Decodable>(_ request: Data) throws -> Input {
    try JSONDecoder().decode(Envelope<Input>.self, from: request).input
}

func day(_ text: String, _ name: String) throws -> Day {
    guard let day = Day(isoString: text) else { throw CallError(description: "invalid \(name) \(text)") }
    return day
}

/// A number from a form, checked before the rules convert it to Int (which would trap out of range).
private func checked(_ value: Double, in range: ClosedRange<Double>, _ name: String) throws -> Double {
    guard range.contains(value) else { throw CallError(description: "\(name) out of range \(value)") }
    return value
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
    // A form can send anything; out of range the rules would trap converting to Int.
    guard Limits.heightCm.contains(input.heightCm) else { throw CallError(description: "heightCm out of range \(input.heightCm)") }
    guard Limits.weightKg.contains(input.weightKg) else { throw CallError(description: "weightKg out of range \(input.weightKg)") }
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

// MARK: - Onboarding, partner setup and Dagdoel (web fase 1)

struct BodyFields: Codable {
    var centimetres: Double?
    var feet: Double?
    var inches: Double?
    var weight: Double?
}

struct StoredBody: Decodable {
    let heightCm: Double
    let weightKg: Double
}

struct BodyInputRequest: Decodable {
    let usesMetric: Bool
    let stored: StoredBody?
    let fields: BodyFields?
}

struct BodyInputAnswer: Encodable {
    let fields: BodyFields
    let heightCm: Double?
    let weightKg: Double?
    /// Each within what the database accepts, for the onboarding step that asks for it alone.
    let heightValid: Bool
    let weightValid: Bool
    let isValid: Bool
}

/// The fields as onboarding and the profile editor show them, and what they store (BodyInput).
func bodyInput(_ request: BodyInputRequest) throws -> BodyInputAnswer {
    var body = request.stored.map { BodyInput(usesMetric: request.usesMetric, heightCm: $0.heightCm, weightKg: $0.weightKg) }
        ?? BodyInput(usesMetric: request.usesMetric)
    if let fields = request.fields {
        body.centimetres = fields.centimetres
        body.feet = fields.feet
        body.inches = fields.inches
        body.weight = fields.weight
    }
    return BodyInputAnswer(
        fields: BodyFields(centimetres: body.centimetres, feet: body.feet, inches: body.inches, weight: body.weight),
        heightCm: body.heightCm, weightKg: body.weightKg,
        heightValid: body.heightCm.map { Limits.heightCm.contains($0) } ?? false,
        weightValid: body.weightKg.map { Limits.weightKg.contains($0) } ?? false,
        isValid: body.isValid
    )
}

struct BirthDayRequest: Decodable {
    let birthDay: String
    let today: String
}

struct BirthDayAnswer: Encodable {
    let age: Int
    let isAdult: Bool
    let isValid: Bool
}

func birthDay(_ request: BirthDayRequest) throws -> BirthDayAnswer {
    let born = try day(request.birthDay, "birthDay")
    let today = try day(request.today, "today")
    return BirthDayAnswer(age: age(bornOn: born, on: today), isAdult: isAdult(bornOn: born, on: today),
                          isValid: isValidBirthDay(born, on: today))
}

struct MacrosRequest: Decodable {
    let kcal: Int
    let weightKg: Double
    let goal: Goal
}

func macros(_ request: MacrosRequest) throws -> NutritionTargets {
    guard Limits.kcal.contains(request.kcal) else { throw CallError(description: "kcal out of range \(request.kcal)") }
    return NutritionEngine.macros(kcal: request.kcal, weightKg: try checked(request.weightKg, in: Limits.weightKg, "weightKg"),
                                  goal: request.goal)
}

struct Shares: Encodable {
    let protein: Double
    let carbs: Double
    let fat: Double
}

func kcalShares(_ targets: NutritionTargets) throws -> Shares {
    let shares = NutritionEngine.kcalShares(of: targets)
    return Shares(protein: shares.protein, carbs: shares.carbs, fat: shares.fat)
}

struct WarningsRequest: Decodable {
    let kcal: Int
    let bmr: Double
    let tdee: Double
    let sex: Sex
}

struct WarningsAnswer: Encodable {
    let warnings: [String]
    let commonMinimumKcal: Int
}

func warnings(_ request: WarningsRequest) throws -> WarningsAnswer {
    guard Limits.kcal.contains(request.kcal), request.bmr.isFinite, request.tdee.isFinite else {
        throw CallError(description: "kcal, bmr or tdee out of range")
    }
    return WarningsAnswer(
        warnings: NutritionEngine.warnings(forKcal: request.kcal, bmr: request.bmr, tdee: request.tdee, sex: request.sex)
            .map(\.rawValue).sorted(),
        commonMinimumKcal: NutritionEngine.commonMinimumKcal(for: request.sex)
    )
}

struct PeriodInput: Decodable {
    let effectiveOn: String
    /// Milliseconds since 1970, as JavaScript's Date.getTime().
    let updatedAtMs: Double
    let targets: NutritionTargets
}

struct TargetsOnDayRequest: Decodable {
    let day: String
    let fallback: NutritionTargets
    let periods: [PeriodInput]
}

func periodEntries(_ periods: [PeriodInput]) throws -> [TargetPeriodEntry] {
    try periods.map { period in
        TargetPeriodEntry(effectiveOn: try day(period.effectiveOn, "effectiveOn"),
                           updatedAt: Date(timeIntervalSince1970: period.updatedAtMs / 1000), targets: period.targets)
    }
}

func targetsOnDay(_ request: TargetsOnDayRequest) throws -> NutritionTargets {
    TargetPeriods.targets(on: try day(request.day, "day"), periods: try periodEntries(request.periods), fallback: request.fallback)
}

struct CreatureRequest: Decodable {
    let level: Int
}

struct CreatureAnswer: Encodable {
    let startShape: Double
    let colorCount: Int
    let growthStage: Int
}

func creature(_ request: CreatureRequest) throws -> CreatureAnswer {
    CreatureAnswer(startShape: CreatureEngine.startShape, colorCount: CreatureEngine.unlockedColorCount(atLevel: request.level),
                   growthStage: CreatureEngine.growthStage(forLevel: request.level))
}

/// Each goal's factor on the total expenditure, so the onboarding text names the same share as the rule.
func goalFactors() -> [String: Double] {
    Dictionary(uniqueKeysWithValues: Goal.allCases.map { ($0.rawValue, $0.kcalFactor) })
}

struct ProfileRules: Encodable {
    let activityFactors: [String: Double]
    let proteinPerKg: [String: Double]
    /// Lowest and highest value of each target the user may type (EditTargetsView).
    let targetLimits: [String: [Int]]
}

func profileRules() -> ProfileRules {
    ProfileRules(
        activityFactors: Dictionary(uniqueKeysWithValues: ActivityLevel.allCases.map { ($0.rawValue, $0.multiplier) }),
        proteinPerKg: Dictionary(uniqueKeysWithValues: Goal.allCases.map { ($0.rawValue, $0.proteinPerKg) }),
        targetLimits: [
            "kcal": [Limits.kcal.lowerBound, Limits.kcal.upperBound],
            "proteinG": [Limits.proteinG.lowerBound, Limits.proteinG.upperBound],
            "carbsG": [Limits.carbsG.lowerBound, Limits.carbsG.upperBound],
            "fatG": [Limits.fatG.lowerBound, Limits.fatG.upperBound],
        ]
    )
}
