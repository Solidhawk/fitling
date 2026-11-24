import Testing
@testable import FitlingCore

/// Kilograms or pounds for training weights, and the body measurements (web phase 4); TrainingTests in the app check
/// the same through WorkoutViewModel and BodyLog.
@Suite struct TrainingUnitsTests {
    @Test func poundsAreStoredAsKilograms() {
        #expect(WeightUnit.pounds.kilograms(from: 135) == 135 * 0.45359237)
        #expect(abs(WeightUnit.pounds.value(fromKilograms: 61.23) - 135) < 0.01)
        #expect(WeightUnit.kilograms.kilograms(from: 60) == 60)
    }

    @Test func aSetNeedsWeightAndReps() {
        #expect(TrainingRecords.canLog(weight: 60, reps: 8))
        #expect(TrainingRecords.canLog(weight: 0, reps: 8))
        #expect(!TrainingRecords.canLog(weight: 60, reps: nil))
        #expect(!TrainingRecords.canLog(weight: nil, reps: 8))
        #expect(!TrainingRecords.canLog(weight: 60, reps: 0))
        #expect(!TrainingRecords.canLog(weight: -1, reps: 8))
    }

    @Test func imperialMeasurementsAreStoredInKilogramsAndCentimetres() {
        #expect(BodyMeasurements.storedValue(176, kind: .weight, usesMetric: false) == 79.8)
        #expect(BodyMeasurements.storedValue(32, kind: .waist, usesMetric: false) == 81.3)
        #expect(abs(BodyMeasurements.displayValue(79.8, kind: .weight, usesMetric: false) - 176) < 0.2)
        #expect(BodyMeasurements.displayValue(81.3, kind: .waist, usesMetric: true) == 81.3)
    }

    @Test func impossibleValuesAreRefused() {
        #expect(BodyMeasurements.storedValue(0, kind: .weight, usesMetric: true) == nil)
        #expect(BodyMeasurements.storedValue(600, kind: .waist, usesMetric: true) == nil)
        #expect(BodyMeasurements.storedValue(80.04, kind: .weight, usesMetric: true) == 80)
        #expect(MeasurementKind.allCases.map(\.rawValue) == ["weight", "waist", "chest", "hips", "arm", "thigh", "neck"])
    }
}
