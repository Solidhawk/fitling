#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The partner for the web (phases 2 and 3): its mood today, folding finished days into XP and shape, and what it wears,
// the same as CreatureHistory and PartnerViewModel on iOS.

struct LoggedEntryInput: Decodable {
    let day: String
    let kcal: Double
    let proteinG: Double?
}

/// The partner's days: the `creatures` row, the entries and workouts, and the targets that applied.
struct PartnerDaysRequest: Decodable {
    /// The `creatures` row: species, colorIndex, tone, createdOn, bodyShape, xp, lastProcessedDay, offTargetDays.
    let creature: CreatureState
    let entries: [LoggedEntryInput]
    /// Days with a finished workout.
    let workoutDays: [String]
    let periods: [PeriodInput]
    let fallback: NutritionTargets
    let today: String

    /// One record per day from `start` through today, each against its own target (CreatureHistory.records).
    func records(from start: Day, through today: Day) throws -> [DayRecord] {
        let periods = try periodEntries(self.periods)
        let entries = try self.entries
            .map { LoggedEntry(day: try day($0.day, "day"), kcal: $0.kcal, proteinG: $0.proteinG) }
            .filter { $0.day >= start && $0.day <= today }
        let workoutDays = Set(try self.workoutDays.map { try day($0, "workoutDay") }.filter { $0 >= start && $0 <= today })
        return DayRecords.build(entries: entries, workoutDays: workoutDays) {
            TargetPeriods.targets(on: $0, periods: periods, fallback: fallback)
        }
    }
}

struct XPOutput: Encodable {
    let logging: Int
    let withinTarget: Int
    let protein: Int
    let workout: Int

    init(_ breakdown: XPBreakdown) {
        logging = breakdown.logging
        withinTarget = breakdown.withinTarget
        protein = breakdown.protein
        workout = breakdown.workout
    }
}

struct ItemOutput: Encodable {
    let item: String
    let unlockLevel: Int
}

struct PartnerSnapshotAnswer: Encodable {
    let mood: String
    let condition: String
    let energy: Double
    let level: Int
    let xp: Int
    let xpIntoLevel: Int
    let xpForNextLevel: Int
    let growthStage: Int
    let bodyShape: Double
    let colorIndex: Int
    let trainedRecently: Bool
    let unlockedItems: [String]
    /// Every accessory in its own order, with the level at which it unlocks (the partner tab lists them all).
    let items: [ItemOutput]
    let unlockedColorCount: Int
    /// The levels at which the colours that are still locked unlock (PartnerViewModel.lockedColorLevels).
    let lockedColorLevels: [Int]
    /// What today earns so far; it is added once the day is over.
    let todayXP: XPOutput
    /// How many days before today decide the mood; older entries are not needed.
    let historyDays: Int
}

/// The partner right now, as CreatureHistory.snapshot: from the last week and today, each day against its own target.
func partnerSnapshot(_ request: PartnerDaysRequest) throws -> PartnerSnapshotAnswer {
    let today = try day(request.today, "today")
    let historyDays = CreatureEngine.windowDays + 1
    let records = try request.records(from: today.adding(-historyDays), through: today)
    let snapshot = CreatureEngine.snapshot(of: request.creature, records: records, today: today)
    let todayXP = records.first { $0.day == today }.map(CreatureEngine.xp(for:)) ?? XPBreakdown()
    return PartnerSnapshotAnswer(
        mood: snapshot.mood.rawValue, condition: snapshot.condition.rawValue, energy: snapshot.energy, level: snapshot.level,
        xp: snapshot.xp, xpIntoLevel: snapshot.xpIntoLevel, xpForNextLevel: snapshot.xpForNextLevel,
        growthStage: snapshot.growthStage, bodyShape: snapshot.bodyShape, colorIndex: snapshot.colorIndex,
        trainedRecently: snapshot.trainedRecently, unlockedItems: snapshot.unlockedItems.map(\.rawValue),
        items: CreatureItem.allCases.map { ItemOutput(item: $0.rawValue, unlockLevel: $0.unlockLevel) },
        unlockedColorCount: snapshot.unlockedColorCount,
        lockedColorLevels: CreatureEngine.lockedColorLevels(atLevel: snapshot.level),
        todayXP: XPOutput(todayXP), historyDays: historyDays
    )
}

struct CreatureRowRequest: Decodable {
    let creature: CreatureState
}

struct AdvanceFromAnswer: Encodable {
    /// The first day whose entries count: the week before the first day still to fold in.
    let firstDay: String
}

/// Where the days to fold in start, so the web reads only those (CreatureHistory.update).
func advanceFrom(_ request: CreatureRowRequest) -> AdvanceFromAnswer {
    let state = request.creature
    return AdvanceFromAnswer(firstDay: CreatureEngine.firstRecordDay(toAdvance: state).isoString)
}

struct EventOutput: Encodable {
    let kind: String
    var level: Int?
    var item: String?
    var index: Int?
    var xp: Int?

    init(_ event: CreatureEvent) {
        switch event {
        case let .leveledUp(reached):
            kind = "leveledUp"
            level = reached
        case let .unlockedItem(unlocked):
            kind = "unlockedItem"
            item = unlocked.rawValue
        case let .unlockedColor(unlocked):
            kind = "unlockedColor"
            index = unlocked
        case let .recoveryBonus(bonus):
            kind = "recoveryBonus"
            xp = bonus
        }
    }
}

struct PartnerAdvanceAnswer: Encodable {
    let creature: CreatureState
    /// False when nothing changed: then nothing is written.
    let changed: Bool
    let events: [EventOutput]
}

/// Folds every finished day into the partner's shape and XP (CreatureEngine.advance, as CreatureHistory.update). The
/// same state and days give the same result, so two devices that both fold the same days write the same row.
func partnerAdvance(_ request: PartnerDaysRequest) throws -> PartnerAdvanceAnswer {
    let today = try day(request.today, "today")
    let state = request.creature
    let start = CreatureEngine.firstRecordDay(toAdvance: state)
    let update = CreatureEngine.advance(state, records: try request.records(from: start, through: today), today: today)
    return PartnerAdvanceAnswer(creature: update.state, changed: update.state != state, events: update.events.map(EventOutput.init))
}

struct WearingRequest: Decodable {
    let worn: [String]
    let item: String
    let unlocked: [String]
}

struct WearingAnswer: Encodable {
    let worn: [String]
}

/// What the partner wears after a tap on an item (CreatureEngine.wearing); unknown names are left out.
func wearing(_ request: WearingRequest) throws -> WearingAnswer {
    guard let item = CreatureItem(rawValue: request.item) else { throw CallError(description: "unknown item \(request.item)") }
    let worn = CreatureEngine.wearing(
        request.worn.compactMap(CreatureItem.init(rawValue:)), toggling: item, unlocked: request.unlocked.compactMap(CreatureItem.init(rawValue:))
    )
    return WearingAnswer(worn: worn.map(\.rawValue))
}
