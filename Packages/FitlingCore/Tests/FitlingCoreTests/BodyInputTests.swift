import Foundation
import Testing
@testable import FitlingCore

@Suite struct BodyInputTests {
    @Test func metricValuesAreStoredWithOneDecimal() {
        var input = BodyInput(usesMetric: true)
        input.centimetres = 180.04
        input.weight = 80.06
        #expect(input.heightCm == 180)
        #expect(input.weightKg == 80.1)
    }

    @Test func imperialHeightAndWeightGiveTheSameValuesAsMetric() {
        var input = BodyInput(usesMetric: false)
        input.feet = 5
        input.inches = 10
        input.weight = 176
        #expect(input.heightCm == 177.8)
        #expect(input.weightKg == 79.8)
    }

    /// Opening the profile editor and saving without touching a field must not change a value.
    @Test func unchangedImperialFieldsGiveBackTheStoredValues() {
        let input = BodyInput(usesMetric: false, heightCm: 180, weightKg: 80)
        #expect(input.feet == 5)
        #expect(input.inches == 10.9)
        #expect(input.weight == 176.4)
        #expect(input.heightCm == 180)
        #expect(input.weightKg == 80)
    }

    @Test func aChangedFieldIsConvertedAgain() {
        var input = BodyInput(usesMetric: false, heightCm: 180, weightKg: 80)
        input.weight = 176
        input.inches = 10
        #expect(input.weightKg == 79.8)
        #expect(input.heightCm == 177.8)
    }

    @Test func inchesNeverShowTwelve() {
        // 182.8 cm is 71.97 in: that is 6 ft 0 in, not 5 ft 12 in.
        let input = BodyInput(usesMetric: false, heightCm: 182.8, weightKg: 80)
        #expect(input.feet == 6)
        #expect(input.inches == 0)
    }

    @Test func outOfRangeValuesAreNotValid() {
        var input = BodyInput(usesMetric: true, heightCm: 180, weightKg: 80)
        #expect(input.isValid)
        input.weight = 20
        #expect(!input.isValid)
        input.weight = nil
        #expect(!input.isValid)
    }
}
