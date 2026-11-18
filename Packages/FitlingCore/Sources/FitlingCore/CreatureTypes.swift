import Foundation

// Raw values are the exact `check` values of the `creatures` table in Supabase.
public enum Species: String, Sendable, CaseIterable, Codable {
    case sprout, ember, pip, pebble
}

/// The voice of the creature's notifications: lief, grappig or coach.
public enum MessageTone: String, Sendable, CaseIterable, Codable {
    case sweet, funny, coach
}

/// The five states from the rolling seven-day average against the kcal target.
public enum CreatureCondition: String, Sendable, CaseIterable, Codable {
    case fit
    case normal
    case tooMuch = "too_much"
    case tooLittle = "too_little"
    case asleep
}

public enum CreatureMood: String, Sendable, CaseIterable, Codable {
    case happy, content, sluggish, tired, hungry, asleep
}

/// What a notification is about. One more than the conditions: "hungry" is the reminder on a
/// day without logs, before the creature falls asleep.
public enum MessageTopic: String, Sendable, CaseIterable, Codable {
    case fit
    case normal
    case tooMuch = "too_much"
    case tooLittle = "too_little"
    case asleep
    case hungry
}

public enum CreatureItem: String, Sendable, CaseIterable, Codable {
    case scarf, cap, bow, glasses, backpack, crown

    public var unlockLevel: Int {
        switch self {
        case .scarf: 2
        case .cap: 4
        case .bow: 6
        case .glasses: 8
        case .backpack: 11
        case .crown: 15
        }
    }
}

/// What the user logged on one day, with the targets that applied on that day.
public struct DayRecord: Sendable, Equatable {
    public var day: Day
    public var kcal: Int
    public var kcalTarget: Int
    public var proteinG: Int
    public var proteinTargetG: Int
    /// Number of logged food entries. Zero means nothing was logged.
    public var entryCount: Int
    public var workoutCompleted: Bool

    public init(day: Day, kcal: Int, kcalTarget: Int, proteinG: Int, proteinTargetG: Int, entryCount: Int, workoutCompleted: Bool) {
        self.day = day
        self.kcal = kcal
        self.kcalTarget = kcalTarget
        self.proteinG = proteinG
        self.proteinTargetG = proteinTargetG
        self.entryCount = entryCount
        self.workoutCompleted = workoutCompleted
    }
}

/// Everything about a creature that is stored. Appearance is derived, never stored.
public struct CreatureState: Sendable, Equatable, Codable {
    public var species: Species
    public var colorIndex: Int
    public var tone: MessageTone
    public var createdOn: Day
    /// 0 is the lean, fit shape; 1 is round. Moves at most one `CreatureEngine.shapeStep` per day.
    public var bodyShape: Double
    public var xp: Int
    /// The last completed day that was folded into shape and XP. Nil until the first one.
    public var lastProcessedDay: Day?
    /// Consecutive processed days in "too much" or "too little", for the recovery bonus.
    public var offTargetDays: Int

    public init(
        species: Species, colorIndex: Int, tone: MessageTone, createdOn: Day,
        bodyShape: Double = CreatureEngine.startShape, xp: Int = 0, lastProcessedDay: Day? = nil, offTargetDays: Int = 0
    ) {
        self.species = species
        self.colorIndex = colorIndex
        self.tone = tone
        self.createdOn = createdOn
        self.bodyShape = bodyShape
        self.xp = xp
        self.lastProcessedDay = lastProcessedDay
        self.offTargetDays = offTargetDays
    }
}

public struct XPBreakdown: Sendable, Equatable {
    public var logging = 0
    public var withinTarget = 0
    public var protein = 0
    public var workout = 0

    public var total: Int { logging + withinTarget + protein + workout }

    public init(logging: Int = 0, withinTarget: Int = 0, protein: Int = 0, workout: Int = 0) {
        self.logging = logging
        self.withinTarget = withinTarget
        self.protein = protein
        self.workout = workout
    }
}

public enum CreatureEvent: Sendable, Equatable {
    case leveledUp(to: Int)
    case unlockedItem(CreatureItem)
    case unlockedColor(index: Int)
    case recoveryBonus(xp: Int)
}

public struct CreatureUpdate: Sendable, Equatable {
    public let state: CreatureState
    public let events: [CreatureEvent]
}

/// What the UI needs to draw the creature. How each value looks is up to the UI.
public struct CreatureSnapshot: Sendable, Equatable {
    public let species: Species
    public let colorIndex: Int
    public let condition: CreatureCondition
    public let mood: CreatureMood
    public let bodyShape: Double
    /// 0 is asleep, 1 is full of energy.
    public let energy: Double
    public let level: Int
    public let xp: Int
    public let xpIntoLevel: Int
    public let xpForNextLevel: Int
    /// 0...4. Sprout grows leaves and flowers, Ember's flame grows, Pip gets feathers and a
    /// crest, Pebble gets moss and crystals.
    public let growthStage: Int
    /// A workout today or yesterday: Ember's flame burns brighter, Sprout carries a flower.
    public let trainedRecently: Bool
    public let unlockedItems: [CreatureItem]
    public let unlockedColorCount: Int
}
