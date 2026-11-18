import Foundation

private let fatShareOfKcal = 0.25
private let kcalPerGramProtein = 4.0
private let kcalPerGramCarbs = 4.0
private let kcalPerGramFat = 9.0

/// Mifflin-St Jeor, with the average of the male and female constants for `.other`.
func basalMetabolicRate(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
    let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
    switch sex {
    case .male: return base + 5
    case .female: return base - 161
    case .other: return base - 78
    }
}

// Compares (month, day) instead of using Calendar.dateComponents(.year): Foundation on Darwin
// and Linux disagree on anniversaries of 29 February. This way a 29 February birthday is
// reached on 1 March in non-leap years, on every platform.
public func age(birthDate: Date, on date: Date, calendar: Calendar) -> Int {
    let born = calendar.dateComponents([.year, .month, .day], from: birthDate)
    let now = calendar.dateComponents([.year, .month, .day], from: date)
    guard let bornYear = born.year, let bornMonth = born.month, let bornDay = born.day,
          let nowYear = now.year, let nowMonth = now.month, let nowDay = now.day else { return 0 }
    let hadBirthday = (nowMonth, nowDay) >= (bornMonth, bornDay)
    return nowYear - bornYear - (hadBirthday ? 0 : 1)
}

public func isAdult(birthDate: Date, on date: Date, calendar: Calendar) -> Bool {
    age(birthDate: birthDate, on: date, calendar: calendar) >= Limits.minimumAge
}

public func safeMinimumKcal(for sex: Sex) -> Int {
    sex == .male ? 1500 : 1200
}

public func calculateEnergy(for profile: BodyProfile, on date: Date, calendar: Calendar) -> EnergyCalculation {
    let bmr = basalMetabolicRate(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: age(birthDate: profile.birthDate, on: date, calendar: calendar),
        sex: profile.sex
    )
    let tdee = bmr * profile.activityLevel.multiplier
    let kcal = Int((tdee * profile.goal.kcalFactor / 10).rounded()) * 10
    let protein = Int((profile.weightKg * profile.goal.proteinPerKg).rounded())
    let fat = Int((Double(kcal) * fatShareOfKcal / kcalPerGramFat).rounded())
    let remainingKcal = Double(kcal) - Double(protein) * kcalPerGramProtein - Double(fat) * kcalPerGramFat
    let carbs = max(0, Int((remainingKcal / kcalPerGramCarbs).rounded()))
    return EnergyCalculation(
        bmr: bmr,
        tdee: tdee,
        targets: NutritionTargets(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat),
        isBelowSafeMinimum: kcal < safeMinimumKcal(for: profile.sex)
    )
}
