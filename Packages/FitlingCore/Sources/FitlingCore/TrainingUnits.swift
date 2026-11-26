/// Kilograms or pounds for training weights, by the user's region. The store always holds kilograms.
public enum WeightUnit: Sendable, Equatable {
    case kilograms, pounds

    public func kilograms(from value: Double) -> Double {
        self == .pounds ? value * BodyInput.kilogramsPerPound : value
    }

    public func value(fromKilograms kilograms: Double) -> Double {
        self == .pounds ? kilograms / BodyInput.kilogramsPerPound : kilograms
    }
}

extension TrainingRecords {
    /// A set can be logged with a weight (0 for none) and at least one rep (WorkoutViewModel.canLog).
    public static func canLog(weight: Double?, reps: Int?) -> Bool {
        guard let weight, let reps else { return false }
        return weight >= 0 && reps > 0
    }
}

/// What can be measured, with the values the `body_measurements` check allows.
public enum MeasurementKind: String, Sendable, CaseIterable, Codable {
    case weight, waist, chest, hips, arm, thigh, neck

    /// Weight is stored in kilograms, the rest in centimetres.
    public var isWeight: Bool { self == .weight }
}

/// Body weight and circumferences (TASKS 4.8): the user types in their own units, the store keeps kilograms and
/// centimetres to a tenth, above 0 and at most 500.
public enum BodyMeasurements {
    /// From the user's unit to kilograms or centimetres. Nil outside what the database accepts.
    public static func storedValue(_ value: Double, kind: MeasurementKind, usesMetric: Bool) -> Double? {
        let stored: Double
        if kind.isWeight {
            stored = usesMetric ? value : WeightUnit.pounds.kilograms(from: value)
        } else {
            stored = usesMetric ? value : value * BodyInput.centimetresPerInch
        }
        let rounded = (stored * 10).rounded() / 10
        return rounded > 0 && rounded <= 500 ? rounded : nil
    }

    /// A stored value in the user's unit.
    public static func displayValue(_ stored: Double, kind: MeasurementKind, usesMetric: Bool) -> Double {
        guard !usesMetric else { return stored }
        return kind.isWeight ? WeightUnit.pounds.value(fromKilograms: stored) : stored / BodyInput.centimetresPerInch
    }
}
