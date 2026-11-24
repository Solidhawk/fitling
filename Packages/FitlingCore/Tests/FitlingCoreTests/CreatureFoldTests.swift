import Testing
@testable import FitlingCore

/// Which days folding needs and which colours are still locked, shared by the app and the web (web phase 3).
@Suite struct CreatureFoldTests {
    @Test func foldingStartsAWeekBeforeTheFirstOpenDay() {
        var state = CreatureState(species: .owl, colorIndex: 0, tone: .sweet, createdOn: Day(isoString: "2026-11-14")!)
        // The engine judges a day by the seven days ending on it.
        #expect(CreatureEngine.firstRecordDay(toAdvance: state) == Day(isoString: "2026-11-08"))
        state.lastProcessedDay = Day(isoString: "2026-11-20")
        #expect(CreatureEngine.firstRecordDay(toAdvance: state) == Day(isoString: "2026-11-14"))
    }

    @Test func lockedColoursAreThoseAboveTheLevel() {
        #expect(CreatureEngine.lockedColorLevels(atLevel: 1) == [5, 12])
        #expect(CreatureEngine.lockedColorLevels(atLevel: 5) == [12])
        #expect(CreatureEngine.lockedColorLevels(atLevel: 12) == [])
    }
}
