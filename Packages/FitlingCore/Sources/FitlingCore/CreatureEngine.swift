#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The creature's rules. The engine returns a state; it never decides how that state looks.
///
/// Two rules protect the user: eating less is never rewarded (no XP, no slimmer shape), and
/// every state has a way back (the creature sleeps but never dies, and XP never goes down).
public enum CreatureEngine {
    public static let startShape = 0.3
    public static let shapeStep = 0.05
    public static let recoveryBonusXP = 150
    /// Days in "too much" or "too little" before a return to "fit" earns the recovery bonus.
    public static let recoveryDays = 7
    public static let daysUntilAsleep = 3
    public static let windowDays = 7
    /// Fewer logged days than this in the window say nothing about a pattern yet.
    public static let minimumDaysForJudgement = 3
    public static let messageVariants = 3
    public static let baseColorCount = 3
    public static let colorUnlockLevels = [5, 12]
    /// The level at which each of the six forms starts.
    public static let growthLevels = [1, 3, 6, 10, 15, 22]
    public static let maxLevel = 50

    private static let loggingXP = 10
    private static let withinTargetXP = 40
    private static let proteinXP = 20
    private static let workoutXP = 30
    /// The average at which the creature is fully round: 150 % of the target.
    private static let roundAtRatio = 1.5
    private static let tooMuchRatio = 1.1
    private static let tooLittleRatio = 0.75
    /// A day under half the target was most likely logged only in part.
    private static let representativeShare = 0.5

    // MARK: Levels

    /// Total XP needed to reach `level`.
    public static func xpRequired(forLevel level: Int) -> Int {
        level <= 1 ? 0 : 50 * level * (level - 1)
    }

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while level < maxLevel, xpRequired(forLevel: level + 1) <= xp {
            level += 1
        }
        return level
    }

    public static func growthStage(forLevel level: Int) -> Int {
        max(0, growthLevels.filter { $0 <= level }.count - 1)
    }

    public static func unlockedItems(atLevel level: Int) -> [CreatureItem] {
        CreatureItem.allCases.filter { $0.unlockLevel <= level }
    }

    public static func unlockedColorCount(atLevel level: Int) -> Int {
        baseColorCount + colorUnlockLevels.filter { $0 <= level }.count
    }

    /// The levels at which the colours that are still locked at `level` unlock.
    public static func lockedColorLevels(atLevel level: Int) -> [Int] {
        colorUnlockLevels.filter { $0 > level }
    }

    /// The first day whose record folding `state` needs: the engine judges a day by the seven days ending on it, so
    /// the week before the first day still to fold in. Shared by CreatureHistory on iOS and the web.
    public static func firstRecordDay(toAdvance state: CreatureState) -> Day {
        (state.lastProcessedDay ?? state.createdOn).adding(-(windowDays - 1))
    }

    /// The XP one day earns. Also usable for today, to show what is already earned.
    public static func xp(for record: DayRecord) -> XPBreakdown {
        var breakdown = XPBreakdown()
        if record.workoutCompleted { breakdown.workout = workoutXP }
        guard record.entryCount > 0 else { return breakdown }
        breakdown.logging = loggingXP
        if record.kcalTarget > 0, record.kcal * 10 >= record.kcalTarget * 9, record.kcal * 10 <= record.kcalTarget * 11 {
            breakdown.withinTarget = withinTargetXP
        }
        if record.proteinTargetG > 0, record.proteinG >= record.proteinTargetG {
            breakdown.protein = proteinXP
        }
        return breakdown
    }

    // MARK: Condition

    /// The condition at the end of `day`, from the seven days ending on it.
    public static func condition(asOf day: Day, records: [DayRecord], createdOn: Day) -> CreatureCondition {
        History(records: records, createdOn: createdOn).judgement(asOf: day).condition
    }

    // MARK: Advancing

    /// Folds every completed day since `lastProcessedDay` into shape and XP. Safe to call as
    /// often as needed: a day is never counted twice.
    public static func advance(_ state: CreatureState, records: [DayRecord], today: Day) -> CreatureUpdate {
        let history = History(records: records, createdOn: state.createdOn)
        let yesterday = today.adding(-1)
        var state = state
        var events: [CreatureEvent] = []
        var day = max(state.createdOn, state.lastProcessedDay?.adding(1) ?? state.createdOn)

        while day <= yesterday {
            let judgement = history.judgement(asOf: day)
            var gained = history.byDay[day].map { xp(for: $0).total } ?? 0

            switch judgement.condition {
            case .fit:
                state.bodyShape = moved(state.bodyShape, towards: 0)
                if state.offTargetDays >= recoveryDays {
                    gained += recoveryBonusXP
                    events.append(.recoveryBonus(xp: recoveryBonusXP))
                }
                state.offTargetDays = 0
            case .tooMuch:
                state.bodyShape = moved(state.bodyShape, towards: 0.5 + 0.5 * overSeverity(judgement.ratio))
                state.offTargetDays += 1
            case .tooLittle:
                // The shape stays as it is: getting slimmer must never be the result of eating too little.
                state.offTargetDays += 1
            case .asleep:
                state.offTargetDays = 0
            case .normal:
                break
            }

            let levelBefore = level(forXP: state.xp)
            state.xp += gained
            let levelAfter = level(forXP: state.xp)
            if levelAfter > levelBefore {
                for reached in (levelBefore + 1)...levelAfter {
                    events.append(.leveledUp(to: reached))
                    events += CreatureItem.allCases.filter { $0.unlockLevel == reached }.map(CreatureEvent.unlockedItem)
                    if let position = colorUnlockLevels.firstIndex(of: reached) {
                        events.append(.unlockedColor(index: baseColorCount + position))
                    }
                }
            }

            state.lastProcessedDay = day
            day = day.adding(1)
        }
        return CreatureUpdate(state: state, events: events)
    }

    // MARK: Snapshot

    /// The creature as it is right now. `state` must be advanced to `today` first.
    public static func snapshot(of state: CreatureState, records: [DayRecord], today: Day) -> CreatureSnapshot {
        let history = History(records: records, createdOn: state.createdOn)
        let yesterday = today.adding(-1)
        let loggedToday = history.isLogged(today)
        let emptyDays = loggedToday ? 0 : history.unloggedRun(endingOn: yesterday)
        let asleep = emptyDays >= daysUntilAsleep
        let judgement = history.windowJudgement(endingOn: yesterday)
        let condition = asleep ? CreatureCondition.asleep : judgement.condition
        let hungry = !asleep && emptyDays >= 1
        let trainedRecently = history.byDay[today]?.workoutCompleted == true || history.byDay[yesterday]?.workoutCompleted == true

        let mood: CreatureMood
        var energy: Double
        switch condition {
        case .asleep:
            mood = .asleep
            energy = 0
        case .fit:
            mood = .happy
            energy = 1
        case .normal:
            mood = .content
            energy = 0.7
        case .tooMuch:
            mood = .sluggish
            energy = 0.6 - 0.3 * overSeverity(judgement.ratio)
        case .tooLittle:
            mood = .tired
            energy = 0.3 - 0.2 * underSeverity(judgement.ratio)
        }
        if hungry { energy = min(energy, 0.4) }
        if trainedRecently, !asleep { energy = min(1, energy + 0.1) }

        let level = level(forXP: state.xp)
        let levelStart = xpRequired(forLevel: level)
        return CreatureSnapshot(
            species: state.species,
            colorIndex: state.colorIndex,
            condition: condition,
            mood: hungry ? .hungry : mood,
            bodyShape: state.bodyShape,
            energy: energy,
            level: level,
            xp: state.xp,
            xpIntoLevel: state.xp - levelStart,
            xpForNextLevel: level < maxLevel ? xpRequired(forLevel: level + 1) - levelStart : 0,
            growthStage: growthStage(forLevel: level),
            trainedRecently: trainedRecently,
            unlockedItems: unlockedItems(atLevel: level),
            unlockedColorCount: unlockedColorCount(atLevel: level)
        )
    }

    // MARK: Messages

    public static func topic(for snapshot: CreatureSnapshot) -> MessageTopic {
        switch snapshot.mood {
        case .asleep: return .asleep
        case .hungry: return .hungry
        case .happy, .content, .sluggish, .tired:
            switch snapshot.condition {
            case .fit: return .fit
            case .normal: return .normal
            case .tooMuch: return .tooMuch
            case .tooLittle: return .tooLittle
            case .asleep: return .asleep
            }
        }
    }

    /// String Catalog keys for one topic and tone: "creature.message.<topic>.<tone>.<n>".
    public static func messageKeys(topic: MessageTopic, tone: MessageTone) -> [String] {
        (1...messageVariants).map { "creature.message.\(topic.keyName).\(tone.rawValue).\($0)" }
    }

    /// The key for `day`. Rotates through the variants, so two days in a row never read the same.
    public static func messageKey(topic: MessageTopic, tone: MessageTone, on day: Day) -> String {
        let index = (day.ordinal % messageVariants + messageVariants) % messageVariants
        return messageKeys(topic: topic, tone: tone)[index]
    }

    // MARK: Helpers

    private static func moved(_ shape: Double, towards target: Double) -> Double {
        let delta = min(max(target - shape, -shapeStep), shapeStep)
        return min(max(shape + delta, 0), 1)
    }

    private static func overSeverity(_ ratio: Double) -> Double {
        min(max((ratio - tooMuchRatio) / (roundAtRatio - tooMuchRatio), 0), 1)
    }

    private static func underSeverity(_ ratio: Double) -> Double {
        min(max((tooLittleRatio - ratio) / (tooLittleRatio - representativeShare), 0), 1)
    }

    private struct Judgement {
        let condition: CreatureCondition
        /// Logged kcal divided by the target over the window; 1 when there is too little to judge.
        let ratio: Double
    }

    private struct History {
        let byDay: [Day: DayRecord]
        let createdOn: Day

        init(records: [DayRecord], createdOn: Day) {
            byDay = Dictionary(records.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
            self.createdOn = createdOn
        }

        func isLogged(_ day: Day) -> Bool {
            (byDay[day]?.entryCount ?? 0) > 0
        }

        /// Days in a row without logs, counting back from `day`. Days before the creature
        /// existed do not count, and counting stops once the creature would be asleep.
        func unloggedRun(endingOn day: Day) -> Int {
            var count = 0
            var cursor = day
            while count < CreatureEngine.daysUntilAsleep, cursor >= createdOn, !isLogged(cursor) {
                count += 1
                cursor = cursor.adding(-1)
            }
            return count
        }

        func judgement(asOf day: Day) -> Judgement {
            if unloggedRun(endingOn: day) >= CreatureEngine.daysUntilAsleep {
                return Judgement(condition: .asleep, ratio: 1)
            }
            return windowJudgement(endingOn: day)
        }

        /// Whole numbers on purpose: 110 % of the target must count as "fit" exactly.
        func windowJudgement(endingOn day: Day) -> Judgement {
            var kcal = 0
            var target = 0
            var days = 0
            for offset in 0..<CreatureEngine.windowDays {
                guard let record = byDay[day.adding(-offset)], record.entryCount > 0, record.kcalTarget > 0,
                      record.kcal * 2 >= record.kcalTarget else { continue }
                kcal += record.kcal
                target += record.kcalTarget
                days += 1
            }
            guard days >= CreatureEngine.minimumDaysForJudgement else {
                return Judgement(condition: .normal, ratio: 1)
            }
            let ratio = Double(kcal) / Double(target)
            if kcal * 10 > target * 11 { return Judgement(condition: .tooMuch, ratio: ratio) }
            if kcal * 4 < target * 3 { return Judgement(condition: .tooLittle, ratio: ratio) }
            if kcal * 10 >= target * 9 { return Judgement(condition: .fit, ratio: ratio) }
            return Judgement(condition: .normal, ratio: ratio)
        }
    }
}

private extension MessageTopic {
    /// Without the underscore of the raw value: String Catalog keys use letters, digits and dots.
    var keyName: String {
        switch self {
        case .fit: "fit"
        case .normal: "normal"
        case .tooMuch: "tooMuch"
        case .tooLittle: "tooLittle"
        case .asleep: "asleep"
        case .hungry: "hungry"
        }
    }
}
