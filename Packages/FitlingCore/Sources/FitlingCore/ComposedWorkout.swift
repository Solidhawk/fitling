import Foundation

/// A workout made by the generator is a programme day of its own, so the workout done on it keeps its
/// name, exercises, sets and reps.
///
/// The day's id says that it is composed and for which focus: a version 8 UUID (the version that is free
/// to fill in) with the focus in the last byte and the rest random. The table needs no column for it,
/// and it holds on every device the day syncs to.
public enum ComposedWorkout {
    /// A focus that was trained this many days before the last composed workout, or fewer, is in the round.
    public static let roundDays = 28

    /// A new id, never the same twice, for a day with a workout for `focus`.
    public static func dayID(for focus: TrainingFocus) -> UUID {
        var bytes = UUID().uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.15 = code(of: focus)
        return UUID(uuid: bytes)
    }

    /// The focus of a composed day. Nil for every other day: those have version 4 or 5.
    public static func focus(of dayID: UUID) -> TrainingFocus? {
        let bytes = dayID.uuid
        guard bytes.6 >> 4 == 8 else { return nil }
        return TrainingFocus.allCases.first { code(of: $0) == bytes.15 }
    }

    /// What to train next: of the focuses in the round, the one done the longest ago. `done` is newest first.
    public static func nextFocus(after done: [(focus: TrainingFocus, day: Day)]) -> TrainingFocus? {
        guard let last = done.first else { return nil }
        var round: [TrainingFocus] = []
        for entry in done where last.day.ordinal - entry.day.ordinal <= roundDays && !round.contains(entry.focus) {
            round.append(entry.focus)
        }
        return round.last
    }

    /// Stored in ids on the server: never change one, give a new focus a new number.
    private static func code(of focus: TrainingFocus) -> UInt8 {
        switch focus {
        case .fullBody: 1
        case .upperBody: 2
        case .lowerBody: 3
        case .push: 4
        case .pull: 5
        case .arms: 6
        }
    }
}
