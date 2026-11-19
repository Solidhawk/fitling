import Foundation
import FitlingCore

/// Height and weight as the user types them, in metric or in feet, inches and pounds. Every
/// conversion lives here, so onboarding and the profile editor store the same values.
struct BodyInput: Equatable {
    static let centimetresPerInch = 2.54
    static let kilogramsPerPound = 0.45359237

    let usesMetric: Bool
    var centimetres: Double?
    var feet: Double?
    var inches: Double?
    /// Kilograms or pounds, following `usesMetric`.
    var weight: Double?

    init(usesMetric: Bool) {
        self.usesMetric = usesMetric
    }

    init(usesMetric: Bool, heightCm: Double, weightKg: Double) {
        self.usesMetric = usesMetric
        if usesMetric {
            centimetres = heightCm
            weight = weightKg
        } else {
            let totalInches = heightCm / Self.centimetresPerInch
            let wholeFeet = (totalInches / 12).rounded(.down)
            feet = wholeFeet
            inches = Self.oneDecimal(totalInches - wholeFeet * 12)
            weight = Self.oneDecimal(weightKg / Self.kilogramsPerPound)
        }
    }

    init(locale: Locale) {
        self.init(usesMetric: locale.measurementSystem == .metric)
    }

    var heightCm: Double? {
        let centimetres = usesMetric ? centimetres : feet.map { ($0 * 12 + (inches ?? 0)) * Self.centimetresPerInch }
        return centimetres.map(Self.oneDecimal)
    }

    var weightKg: Double? {
        weight.map { Self.oneDecimal(usesMetric ? $0 : $0 * Self.kilogramsPerPound) }
    }

    /// Both values present and within what the database accepts.
    var isValid: Bool {
        guard let heightCm, let weightKg else { return false }
        return Limits.heightCm.contains(heightCm) && Limits.weightKg.contains(weightKg)
    }

    var massUnit: UnitMass { usesMetric ? .kilograms : .pounds }

    /// The database keeps one decimal.
    static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
