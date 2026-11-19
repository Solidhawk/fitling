import Foundation
import FitlingCore

extension BodyInput {
    init(locale: Locale) {
        self.init(usesMetric: locale.measurementSystem == .metric)
    }

    var massUnit: UnitMass { usesMetric ? .kilograms : .pounds }
}
