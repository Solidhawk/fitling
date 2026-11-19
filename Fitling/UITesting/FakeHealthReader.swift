#if DEBUG
import Foundation
import FitlingCore

/// Workout energy without Apple Health: the simulator in CI has no workouts and cannot answer
/// the permission question.
final class FakeHealthReader: HealthReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _grantsAccess = true
    private var _energy: [Day: Double] = [:]

    var grantsAccess: Bool {
        get { lock.withLock { _grantsAccess } }
        set { lock.withLock { _grantsAccess = newValue } }
    }

    var energy: [Day: Double] {
        get { lock.withLock { _energy } }
        set { lock.withLock { _energy = newValue } }
    }

    func requestAccess() async -> Bool {
        grantsAccess
    }

    func workoutEnergy(from start: Day, through end: Day, timeZone: TimeZone) async throws -> [Day: Double] {
        energy.filter { $0.key >= start && $0.key <= end }
    }
}
#endif
