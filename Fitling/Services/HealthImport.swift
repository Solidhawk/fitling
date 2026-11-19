import Foundation
import HealthKit
import SwiftData
import FitlingCore

/// Reads workout energy from Apple Health. Read only: nothing is written to Health, and nothing
/// read from it leaves the device (D-19). A fake stands in for it in the tests.
protocol HealthReading: Sendable {
    func requestAccess() async -> Bool
    /// Active energy of workouts per day, in kcal, for the days from `start` through `end`.
    func workoutEnergy(from start: Day, through end: Day, timeZone: TimeZone) async throws -> [Day: Double]
}

struct HealthKitReader: HealthReading {
    /// One store for the app, as Apple recommends; queries run on it after this call returns.
    nonisolated(unsafe) private static let store = HKHealthStore()

    func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount)]
        return await withCheckedContinuation { continuation in
            Self.store.requestAuthorization(toShare: [], read: types) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func workoutEnergy(from start: Day, through end: Day, timeZone: TimeZone) async throws -> [Day: Double] {
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = start.components
        let last = end.adding(1).components
        guard let from = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day)),
              let to = calendar.date(from: DateComponents(year: last.year, month: last.month, day: last.day)) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var energy: [Day: Double] = [:]
                for case let workout as HKWorkout in samples ?? [] {
                    let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    energy[Day(workout.startDate, timeZone: timeZone), default: 0] += kcal
                }
                continuation.resume(returning: energy)
            }
            Self.store.execute(query)
        }
    }
}

/// Copies workout energy per day into `DayActivity`, where the daily target picks it up when
/// the user counts workouts (`countsWorkoutEnergy`).
@MainActor
struct HealthImport {
    static let daysBack = 14

    let context: ModelContext
    let reader: any HealthReading
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init

    func run() async {
        let today = Day(now(), timeZone: timeZone)
        guard let energy = try? await reader.workoutEnergy(from: today, through: today.adding(-1), timeZone: timeZone), energy.isEmpty == false,
              let _ = try? await reader.workoutEnergy(from: today.adding(-Self.daysBack), through: today, timeZone: timeZone) else { return }
        for offset in 0...Self.daysBack {
            let day = today.adding(-offset)
            let kcal = (energy[day] ?? 0).rounded()
            let key = day.isoString
            var descriptor = FetchDescriptor<DayActivity>(predicate: #Predicate<DayActivity> { $0.day == key })
            descriptor.fetchLimit = 1
            if let activity = try? context.fetch(descriptor).first {
                guard activity.workoutKcal != kcal else { continue }
                activity.workoutKcal = kcal
                activity.updatedAt = now()
            } else if kcal > 0 {
                context.insert(DayActivity(day: day, workoutKcal: kcal, updatedAt: now()))
            }
        }
        try? context.save()
    }
}
