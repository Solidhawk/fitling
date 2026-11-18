import Foundation

/// The creature's rules. The engine returns a state; it never decides how that state looks.
public enum CreatureEngine {
    public static let startShape = 0.3
    public static let shapeStep = 0.05
    public static let recoveryBonusXP = 150
    public static let daysUntilAsleep = 3
    public static let messageVariants = 3
    public static let baseColorCount = 3
    public static let growthLevels = [1, 3, 6, 10, 15]
    public static let maxLevel = 50

    /// Total XP needed to reach `level`.
    public static func xpRequired(forLevel level: Int) -> Int {
        0
    }

    public static func level(forXP xp: Int) -> Int {
        0
    }

    public static func growthStage(forLevel level: Int) -> Int {
        0
    }

    public static func unlockedItems(atLevel level: Int) -> [CreatureItem] {
        []
    }

    public static func unlockedColorCount(atLevel level: Int) -> Int {
        0
    }

    /// The XP one day earns. Also usable for today, to show what is already earned.
    public static func xp(for record: DayRecord) -> XPBreakdown {
        XPBreakdown()
    }

    /// The condition at the end of `day`, from the seven days ending on it.
    public static func condition(asOf day: Day, records: [DayRecord], createdOn: Day) -> CreatureCondition {
        .normal
    }

    /// Folds every completed day since `lastProcessedDay` into shape and XP. Safe to call as
    /// often as needed: a day is never counted twice.
    public static func advance(_ state: CreatureState, records: [DayRecord], today: Day) -> CreatureUpdate {
        CreatureUpdate(state: state, events: [])
    }

    /// The creature as it is right now. `state` must be advanced to `today` first.
    public static func snapshot(of state: CreatureState, records: [DayRecord], today: Day) -> CreatureSnapshot {
        CreatureSnapshot(
            species: state.species, colorIndex: state.colorIndex, condition: .normal, mood: .content,
            bodyShape: 0, energy: 0, level: 0, xp: 0, xpIntoLevel: 0, xpForNextLevel: 0,
            growthStage: 0, trainedRecently: false, unlockedItems: [], unlockedColorCount: 0
        )
    }

    public static func topic(for snapshot: CreatureSnapshot) -> MessageTopic {
        .normal
    }

    /// String Catalog keys for one topic and tone: "creature.message.<topic>.<tone>.<n>".
    public static func messageKeys(topic: MessageTopic, tone: MessageTone) -> [String] {
        []
    }

    /// The key for `day`. Rotates through the variants, so two days in a row never read the same.
    public static func messageKey(topic: MessageTopic, tone: MessageTone, on day: Day) -> String {
        ""
    }
}
