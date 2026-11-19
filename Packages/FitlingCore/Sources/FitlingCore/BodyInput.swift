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
    /// The stored values the fields were filled from. As long as a field still shows its
    /// converted value, the stored value comes back unchanged: converting to inches and pounds
    /// and back would otherwise move it by a tenth.
    private var stored: Stored?

    private struct Stored: Equatable, Sendable {
        var centimetres: Double?
        var feet: Double?
        var inches: Double?
        var weight: Double?
        var heightCm: Double
        var weightKg: Double
    }

    public init(usesMetric: Bool) {
        self.usesMetric = usesMetric
    }

    public init(usesMetric: Bool, heightCm: Double, weightKg: Double) {
        self.usesMetric = usesMetric
        if usesMetric {
            centimetres = heightCm
            weight = weightKg
        } else {
            // Rounded before splitting, so 71.97 in becomes 6 ft 0 in and never 5 ft 12 in.
            let totalInches = Self.oneDecimal(heightCm / Self.centimetresPerInch)
            let wholeFeet = (totalInches / 12).rounded(.down)
            feet = wholeFeet
            inches = Self.oneDecimal(totalInches - wholeFeet * 12)
            weight = Self.oneDecimal(weightKg / Self.kilogramsPerPound)
        }
        stored = Stored(centimetres: centimetres, feet: feet, inches: inches, weight: weight, heightCm: heightCm, weightKg: weightKg)
    }

    public var heightCm: Double? {
        if let stored, stored.centimetres == centimetres, stored.feet == feet, stored.inches == inches {
            return stored.heightCm
        }
        let centimetres = usesMetric ? centimetres : feet.map { ($0 * 12 + (inches ?? 0)) * Self.centimetresPerInch }
        return centimetres.map(Self.oneDecimal)
    }

    public var weightKg: Double? {
        if let stored, stored.weight == weight {
            return stored.weightKg
        }
        return weight.map { Self.oneDecimal(usesMetric ? $0 : $0 * Self.kilogramsPerPound) }
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
