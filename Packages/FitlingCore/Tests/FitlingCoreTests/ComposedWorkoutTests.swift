import Foundation
import Testing
@testable import FitlingCore

/// Each composed workout has its own programme day (UNFORGET S30).
@Suite struct ComposedWorkoutTests {
    @Test func aDayKnowsItsFocus() {
        for focus in TrainingFocus.allCases {
            #expect(ComposedWorkout.focus(of: ComposedWorkout.dayID(for: focus)) == focus)
        }
    }

    /// Never the same id twice: not for two workouts on one device, not on two devices that are offline.
    @Test func everyWorkoutGetsANewID() {
        let ids = (0..<1000).map { _ in ComposedWorkout.dayID(for: .push) }
        #expect(Set(ids).count == ids.count)
    }

    /// The last byte is stored on the server: a later change must not give old workouts another focus.
    @Test func theCodeOfEachFocusNeverChanges() throws {
        let codes: [(String, TrainingFocus)] = [
            ("01", .fullBody), ("02", .upperBody), ("03", .lowerBody), ("04", .push), ("05", .pull), ("06", .arms),
        ]
        for (code, focus) in codes {
            let id = try #require(UUID(uuidString: "3b70d0ec-e441-8831-808c-0c025c473e\(code)"))
            #expect(ComposedWorkout.focus(of: id) == focus)
        }
    }

    @Test func daysOfOtherProgrammesAreNotComposed() throws {
        for _ in 0..<1000 {
            #expect(ComposedWorkout.focus(of: UUID()) == nil)
        }
        // Version 5 is what the ready-made programmes have; an unknown code is no focus either.
        for text in ["3b70d0ec-e441-5831-808c-0c025c473e01", "3b70d0ec-e441-8831-808c-0c025c473e63"] {
            #expect(ComposedWorkout.focus(of: try #require(UUID(uuidString: text))) == nil)
        }
    }

    @Test func withoutComposedWorkoutsThereIsNoNext() {
        #expect(ComposedWorkout.nextFocus(after: []) == nil)
    }

    @Test func theSameFocusEveryTimeStaysThat() {
        let done = [(focus: TrainingFocus.fullBody, day: day(2026, 11, 22)), (focus: .fullBody, day: day(2026, 11, 20))]
        #expect(ComposedWorkout.nextFocus(after: done) == .fullBody)
    }

    @Test func alternatingFocusesTakeTurns() {
        let afterLower = [
            (focus: TrainingFocus.lowerBody, day: day(2026, 11, 22)), (focus: .upperBody, day: day(2026, 11, 20)),
            (focus: .lowerBody, day: day(2026, 11, 18)),
        ]
        #expect(ComposedWorkout.nextFocus(after: afterLower) == .upperBody)
    }

    @Test func pushPullLegsGoRound() {
        let done = [
            (focus: TrainingFocus.pull, day: day(2026, 11, 22)), (focus: .push, day: day(2026, 11, 21)),
            (focus: .lowerBody, day: day(2026, 11, 20)), (focus: .pull, day: day(2026, 11, 19)),
        ]
        #expect(ComposedWorkout.nextFocus(after: done) == .lowerBody)
    }

    @Test func twoOnOneDayGoByTheirOrder() {
        let done = [(focus: TrainingFocus.arms, day: day(2026, 11, 22)), (focus: .lowerBody, day: day(2026, 11, 22))]
        #expect(ComposedWorkout.nextFocus(after: done) == .lowerBody)
    }

    @Test func aFocusFromOverFourWeeksBeforeIsNoLongerInTheRound() {
        let done = [(focus: TrainingFocus.upperBody, day: day(2026, 11, 22)), (focus: .arms, day: day(2026, 10, 24))]
        #expect(ComposedWorkout.nextFocus(after: done) == .upperBody)
    }

    @Test func afterABreakTheRoundPicksUpWhereItWas() {
        let done = [(focus: TrainingFocus.upperBody, day: day(2026, 6, 10)), (focus: .lowerBody, day: day(2026, 6, 8))]
        #expect(ComposedWorkout.nextFocus(after: done) == .lowerBody)
    }
}
