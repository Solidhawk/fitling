#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import FitlingCore

/// Launch arguments for the UI test: the simulator in CI cannot sign in for real, so the app runs
/// on `FakeAuthProvider`, `FakeRemoteStore` and an in-memory store. Never compiled into a release build.
@MainActor
enum UITestEnvironment {
    /// `--ui-testing-on-disk` keeps the database in a real file, as on a device.
    /// `--ui-testing-with-profile` starts signed in with a finished onboarding and a partner, on the home screen.
    /// `--ui-testing-partner-gallery` shows every species in every look, for approving the drawings.
    /// `--ui-testing-workout-history` adds four weeks of finished workouts, so the coach has something to say.
    /// `--ui-testing-animated-exercises` adds one workout of every animated exercise, so each can be opened.
    /// `--ui-testing-reduce-motion` acts as if Reduce Motion is on; XCUITest cannot switch that setting on.
    /// `--ui-testing-dark` forces dark mode; setting the appearance from XCUITest did not reach the app on the CI simulator.
    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-dark") ? .dark : nil
    }

    static var reducesMotion: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion")
    }

    static func makeIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppEnvironment? {
        let state: AuthState
        if arguments.contains("--ui-testing-signed-out") {
            state = .signedOut
        } else if arguments.contains("--ui-testing") || arguments.contains("--ui-testing-with-profile") {
            state = .signedIn(userID: UUID(), usesApple: false)
        } else {
            return nil
        }
        let container = try makeModelContainer(inMemory: !arguments.contains("--ui-testing-on-disk"))
        let sync = SyncEngine(container: container, remote: FakeRemoteStore(), tables: SyncTables.all)
        if arguments.contains("--ui-testing-with-profile"), case let .signedIn(userID, _) = state {
            insertSampleProfile(userID: userID, into: sync)
            if arguments.contains("--ui-testing-workout-history") {
                insertWorkoutHistory(userID: userID, into: sync.context)
            }
            if arguments.contains("--ui-testing-animated-exercises") {
                insertAnimatedExerciseHistory(userID: userID, into: sync.context)
            }
        }
        let source = FakeProductSource()
        source.products[sampleProduct.gtin ?? ""] = sampleProduct
        let food = FoodServices(source: source, search: FakeProductSearch())
        let offerSource = FakeOfferSource()
        offerSource.offerRecords = FakeOfferSource.sample(today: Day(.now, timeZone: .current))
        let root = RootViewModel(auth: FakeAuthProvider(state: state), sync: sync, food: food, reminders: FakeReminderDelivery(), health: FakeHealthReader(),
            shopping: ShoppingServices(sharing: FakeListSharing(), offers: offerSource)
        )
        return AppEnvironment(container: container, root: root)
    }

    /// The product the UI test scans: a real Open Food Facts answer (the lookup-product fixture).
    static let sampleProduct = ProductRecord(
        id: UUID(), ownerID: nil, source: "off", sourceID: "8712100849084", gtin: "8712100849084",
        name: LocalizedText(["de": "Double Caramel"]), brand: "Magnum, Unilever", searchName: "double caramel magnum, unilever",
        quantityUnit: "ml", servingSize: 88, servingLabel: nil, kcal100: 338, protein100: 3.2, carbs100: 36, sugars100: 33,
        fat100: 20, saturatedFat100: 14, fiber100: nil, salt100: 0.17, imageURL: nil, isVerified: true,
        fetchedAt: .now, updatedAt: .now, deletedAt: nil, syncedAt: .now
    )

    /// Bench press and lateral raises done two days ago with every set at the top of the range (go
    /// heavier), and a squat that stayed under its best for four sessions (try another exercise).
    static func insertWorkoutHistory(userID: UUID, into context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now, timeZone: TimeZone = .current) {
        SportCatalog.bundled()?.install(into: context, defaults: defaults, now: now)
        let shared = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.ownerID == nil }))) ?? []
        func exercise(_ english: String) -> Exercise? { shared.first { $0.name.values["en"] == english } }
        let today = Day(now, timeZone: timeZone)

        func workout(_ english: String, daysAgo: Int, kg: Double, reps: Int, sets: Int = 3) {
            guard let exercise = exercise(english) else { return }
            let startedAt = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            let session = WorkoutSession(id: UUID(), userID: userID, programDayID: nil, performedOn: today.adding(-daysAgo), startedAt: startedAt, updatedAt: now)
            session.endedAt = startedAt.addingTimeInterval(3_600)
            context.insert(session)
            for position in 0..<sets {
                context.insert(WorkoutSet(
                    id: UUID(), userID: userID, sessionID: session.id, exerciseID: exercise.id, position: position,
                    weightKg: kg, reps: reps, rpe: 7, isWarmup: false, updatedAt: now
                ))
            }
        }

        workout("Barbell back squat", daysAgo: 20, kg: 100, reps: 8)
        for daysAgo in [16, 12, 8, 4] {
            workout("Barbell back squat", daysAgo: daysAgo, kg: 100, reps: 7)
        }
        workout("Bench press", daysAgo: 2, kg: 60, reps: 12)
        workout("Lateral raise", daysAgo: 2, kg: 8, reps: 12)
        try? context.save()
    }

    /// One finished workout three days ago with every animated exercise in it: "Per oefening" only lists
    /// exercises that were done.
    static func insertAnimatedExerciseHistory(userID: UUID, into context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now, timeZone: TimeZone = .current) {
        SportCatalog.bundled()?.install(into: context, defaults: defaults, now: now)
        let shared = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.ownerID == nil }))) ?? []
        let startedAt = now.addingTimeInterval(-3 * 86_400)
        let session = WorkoutSession(id: UUID(), userID: userID, programDayID: nil, performedOn: Day(now, timeZone: timeZone).adding(-3), startedAt: startedAt, updatedAt: now)
        session.endedAt = startedAt.addingTimeInterval(3_600)
        context.insert(session)
        for (position, exercise) in shared.filter({ ExerciseAnimation.named($0.id) != nil }).enumerated() {
            context.insert(WorkoutSet(
                id: UUID(), userID: userID, sessionID: session.id, exerciseID: exercise.id, position: position,
                weightKg: 20, reps: 10, rpe: 7, isWarmup: false, updatedAt: now
            ))
        }
        try? context.save()
    }

    private static func insertSampleProfile(userID: UUID, into sync: SyncEngine) {
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        let targets = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        sync.context.insert(UserProfile(id: userID, healthConsentAt: .now, healthConsentVersion: 1, body: body, targets: targets, targetsAreManual: false, updatedAt: .now))
        sync.context.recordTargets(targets, for: userID, from: Day(.now, timeZone: .current), at: .now)
        let partner = CreatureState(species: .owl, colorIndex: 0, tone: .sweet, createdOn: Day(.now, timeZone: .current))
        sync.context.insert(Creature(userID: userID, name: "Pip", state: partner, updatedAt: .now))
        try? sync.context.save()
    }
}
#endif
