import Foundation
import Observation
import SwiftData
import FitlingCore

/// The training tab: the workout under way, the next one, the programmes, recent workouts and
/// whether workouts from Apple Health count towards the daily target.
@Observable
@MainActor
final class TrainingViewModel {
    private(set) var programs: [Program] = []
    private(set) var activeSession: WorkoutSession?
    private(set) var next: (program: Program, day: ProgramDay)?
    private(set) var recent: [WorkoutSession] = []
    private(set) var healthRefused = false

    let profile: UserProfile
    let store: TrainingStore
    private let health: any HealthReading

    init(profile: UserProfile, context: ModelContext, health: any HealthReading, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.health = health
        store = TrainingStore(context: context, userID: profile.id, timeZone: timeZone, now: now)
    }

    var countsWorkoutEnergy: Bool {
        profile.countsWorkoutEnergy
    }

    func reload() {
        SportCatalog.bundled()?.install(into: store.context)
        programs = store.programs()
        activeSession = store.activeSession()
        next = store.nextDay()
        recent = store.finishedSessions(limit: 10)
    }

    func start(_ day: ProgramDay?) -> WorkoutSession {
        if let activeSession { return activeSession }
        let session = store.start(day)
        activeSession = session
        return session
    }

    func title(of session: WorkoutSession) -> LocalizedText? {
        session.programDayID.flatMap { store.day($0)?.name }
    }

    func setCount(of session: WorkoutSession) -> Int {
        store.sets(of: session).filter { !$0.isWarmup }.count
    }

    /// Turning it on asks Apple Health for access first and reads the last two weeks.
    func setCountsWorkoutEnergy(_ isOn: Bool) async {
        healthRefused = false
        if isOn {
            _ = await health.requestAccess()
        }
        profile.countsWorkoutEnergy = isOn
        profile.updatedAt = store.now()
        profile.needsPush = true
        try? store.context.save()
        if isOn { await importHealth() }
    }

    func importHealth() async {
        guard profile.countsWorkoutEnergy else { return }
        await HealthImport(context: store.context, reader: health, timeZone: store.timeZone, now: store.now).run()
    }
}
