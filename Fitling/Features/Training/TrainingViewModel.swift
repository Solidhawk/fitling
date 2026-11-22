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
    private(set) var next: NextWorkout?
    private(set) var recent: [WorkoutSession] = []
    private(set) var healthRefused = false
    private(set) var coachNotes: [CoachNote] = []
    /// How long the user wants to train, kept for the next time on this device.
    var workoutMinutes: Int {
        didSet { defaults.set(workoutMinutes, forKey: Self.workoutMinutesKey) }
    }

    let profile: UserProfile
    let store: TrainingStore
    private let health: any HealthReading
    private let defaults: UserDefaults

    init(
        profile: UserProfile, context: ModelContext, health: any HealthReading, defaults: UserDefaults = .standard,
        timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init
    ) {
        self.profile = profile
        self.health = health
        self.defaults = defaults
        store = TrainingStore(context: context, userID: profile.id, timeZone: timeZone, now: now)
        let remembered = defaults.integer(forKey: Self.workoutMinutesKey)
        workoutMinutes = WorkoutBuilder.durations.contains(remembered) ? remembered : WorkoutBuilder.defaultMinutes
    }

    var countsWorkoutEnergy: Bool {
        profile.countsWorkoutEnergy
    }

    func reload() {
        SportCatalog.bundled()?.install(into: store.context)
        programs = store.programs()
        activeSession = store.activeSession()
        next = store.nextWorkout()
        recent = store.finishedSessions(limit: 10)
        coachNotes = store.coachNotes()
    }

    private static let workoutMinutesKey = "fitling.workoutMinutes"

    /// The workout for `focus` in the chosen time, to show before it starts.
    func plan(for focus: TrainingFocus) -> WorkoutPlan {
        WorkoutBuilder.plan(focus, minutes: workoutMinutes, from: store.workoutCandidates(), history: store.workoutHistory())
    }

    /// Makes the workout for `focus` a day of its own and starts it.
    func startComposed(_ focus: TrainingFocus) -> WorkoutSession {
        // Checked first: a day is only made for a workout that starts.
        if let running = store.activeSession() {
            activeSession = running
            return running
        }
        let day = store.compose(
            plan(for: focus).exercises, for: focus,
            programName: String(localized: "training.compose.program"), dayName: String(localized: focus.titleResource)
        )
        reload()
        return start(day)
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
            guard await health.requestAccess() else {
                healthRefused = true
                return
            }
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
