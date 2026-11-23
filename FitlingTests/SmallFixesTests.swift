import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// "1 stuks" on the shopping list and in recipes (UNFORGET S25).
@Suite struct PieceAmountTests {
    func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
        return try #require(Bundle(path: path))
    }

    @Test func onePieceIsSingular() throws {
        #expect(ShoppingAmount.text(1, "piece", bundle: try bundle("nl")) == "1 stuk")
        #expect(ShoppingAmount.text(1, "piece", bundle: try bundle("en")) == "1 pc")
        #expect(ShoppingAmount.text(1, "piece", bundle: try bundle("de")) == "1 Stück")
    }

    @Test func morePiecesArePlural() throws {
        #expect(ShoppingAmount.text(2, "piece", bundle: try bundle("nl")) == "2 stuks")
        #expect(ShoppingAmount.text(2, "piece", bundle: try bundle("en")) == "2 pcs")
        #expect(ShoppingAmount.text(2, "piece", bundle: try bundle("de")) == "2 Stück")
    }

    /// What is shown decides: a sum of recipe amounts such as 1,004 is shown as "1", so it is "1 stuk", not "1 stuks".
    @Test func anAmountShownAsOneIsSingular() throws {
        #expect(ShoppingAmount.text(1.004, "piece", bundle: try bundle("nl")) == "1 stuk")
        #expect(ShoppingAmount.text(0.999, "piece", bundle: try bundle("nl")) == "1 stuk")
        #expect(ShoppingAmount.text(1.01, "piece", bundle: try bundle("nl")).hasSuffix(" stuks"))
    }

    /// Half a piece is not one: "0,5 stuks", as Dutch says it.
    @Test func aPartOfAPieceIsPlural() throws {
        #expect(ShoppingAmount.text(0.5, "piece", bundle: try bundle("nl")).hasSuffix(" stuks"))
        #expect(ShoppingAmount.text(1.5, "piece", bundle: try bundle("nl")).hasSuffix(" stuks"))
    }
}

/// Two workouts on one day with the same exercise keep their order (UNFORGET S26).
@MainActor
@Suite struct SameDayHistoryTests {
    @Test func workoutsOnTheSameDayGoByTheirStart() throws {
        let fixture = try TrainingFixture()
        try fixture.installCatalog()
        let bench = try fixture.exercise("Bench press")
        let morning = fixture.now.addingTimeInterval(-10 * 3_600)
        // Five on one day, inserted last first: by luck alone they come out right once in 120 times.
        for hour in (0..<5).reversed() {
            let session = WorkoutSession(
                id: UUID(), userID: fixture.userID, programDayID: nil, performedOn: fixture.today,
                startedAt: morning.addingTimeInterval(TimeInterval(hour * 3_600)), updatedAt: fixture.now
            )
            session.endedAt = session.startedAt.addingTimeInterval(1_800)
            fixture.context.insert(session)
            fixture.context.insert(WorkoutSet(
                id: UUID(), userID: fixture.userID, sessionID: session.id, exerciseID: bench.id, position: 0,
                weightKg: Double(60 + hour * 5), reps: 8, rpe: 7, isWarmup: false, updatedAt: fixture.now
            ))
        }
        try fixture.context.save()
        let weights = fixture.store.history(of: bench.id).flatMap { $0.sets.map(\.weightKg) }
        #expect(weights == [60, 65, 70, 75, 80])
    }
}

/// The programme of composed workouts says what it is, not "1 dag per week".
@MainActor
@Suite struct ComposedProgrammeLabelTests {
    @Test func itCountsItsWorkouts() throws {
        let fixture = try TrainingFixture()
        try fixture.installCatalog()
        let store = fixture.store
        let bench = try fixture.exercise("Bench press")
        let plan = [PlannedExercise(exerciseID: bench.id, sets: 3, repRange: 6...10, restSeconds: 150)]
        let first = store.compose(plan, for: .push, programName: "Samengesteld", dayName: "Duwen")
        store.compose(plan, for: .upperBody, programName: "Samengesteld", dayName: "Bovenlichaam")
        let program = try #require(store.program(first.programID))
        #expect(store.composedWorkoutCount(of: program) == 2)
    }

    @Test func otherProgrammesAreNotComposed() throws {
        let fixture = try TrainingFixture()
        try fixture.installCatalog()
        let store = fixture.store
        let own = store.createProgram(named: "Eigen", daysPerWeek: 3) { "Dag \($0)" }
        #expect(store.composedWorkoutCount(of: own) == nil)
        #expect(store.programs().filter { $0.ownerID == nil }.allSatisfy { store.composedWorkoutCount(of: $0) == nil })
    }
}
