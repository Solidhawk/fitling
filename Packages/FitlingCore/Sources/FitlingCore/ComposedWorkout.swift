import Foundation

/// A workout made by the generator, kept as a programme day of its own.
public enum ComposedWorkout {
    public static func dayID(for focus: TrainingFocus) -> UUID {
        UUID()
    }

    public static func focus(of dayID: UUID) -> TrainingFocus? {
        nil
    }

    public static func nextFocus(after done: [(focus: TrainingFocus, day: Day)]) -> TrainingFocus? {
        nil
    }
}
