import Foundation

/// Height and weight as the user types them, in metric or in feet, inches and pounds. Every
/// conversion lives here, so onboarding and the profile editor store the same values.
public struct BodyInput: Equatable, Sendable {
    public static let centimetresPerInch = 2.54
    public static let kilogramsPerPound = 0.45359237

    public let usesMetric: Bool
    public var centimetres: Double?
    public var feet: Double?
    public var inches: Double?
    /// Kilograms or pounds, following `usesMetric`.
    public var weight: Double?

    public init(usesMetric: Bool) {
        self.usesMetric = usesMetric
    }

    public init(usesMetric: Bool, heightCm: Double, weightKg: Double) {
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

    public var heightCm: Double? {
        let centimetres = usesMetric ? centimetres : feet.map { ($0 * 12 + (inches ?? 0)) * Self.centimetresPerInch }
        return centimetres.map(Self.oneDecimal)
    }

    public var weightKg: Double? {
        weight.map { Self.oneDecimal(usesMetric ? $0 : $0 * Self.kilogramsPerPound) }
    }

    /// Both values present and within what the database accepts.
    public var isValid: Bool {
        guard let heightCm, let weightKg else { return false }
        return Limits.heightCm.contains(heightCm) && Limits.weightKg.contains(weightKg)
    }

    /// The database keeps one decimal.
    public static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
