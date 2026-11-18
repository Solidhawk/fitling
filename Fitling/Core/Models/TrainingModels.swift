import Foundation
import SwiftData
import FitlingCore

extension FitlingSchemaV1 {
    /// A shared exercise (`ownerID` is nil) or one the user added.
    @Model
    final class Exercise {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID?
        var nameJSON: Data
        var instructionsJSON: Data
        var kind: String
        var loadType: String
        var equipment: String
        var primaryMuscles: [String]
        var secondaryMuscles: [String]
        var defaultStepKg: Double
        var imageURL: String?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, ownerID: UUID?, name: LocalizedText, kind: ExerciseKind, loadType: LoadType, equipment: String,
            primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup], defaultStepKg: Double, updatedAt: Date
        ) {
            self.id = id
            self.ownerID = ownerID
            self.nameJSON = name.json
            self.instructionsJSON = LocalizedText().json
            self.kind = kind.rawValue
            self.loadType = loadType.rawValue
            self.equipment = equipment
            self.primaryMuscles = primaryMuscles.map(\.rawValue)
            self.secondaryMuscles = secondaryMuscles.map(\.rawValue)
            self.defaultStepKg = defaultStepKg
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    /// A ready-made programme (`ownerID` is nil) or the user's own.
    @Model
    final class Program {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID?
        var nameJSON: Data
        var daysPerWeek: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, ownerID: UUID?, name: LocalizedText, daysPerWeek: Int, updatedAt: Date) {
            self.id = id
            self.ownerID = ownerID
            self.nameJSON = name.json
            self.daysPerWeek = daysPerWeek
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    @Model
    final class ProgramDay {
        @Attribute(.unique) var id: UUID
        var programID: UUID
        var ownerID: UUID?
        var nameJSON: Data
        var position: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, programID: UUID, ownerID: UUID?, name: LocalizedText, position: Int, updatedAt: Date) {
            self.id = id
            self.programID = programID
            self.ownerID = ownerID
            self.nameJSON = name.json
            self.position = position
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    @Model
    final class ProgramExercise {
        @Attribute(.unique) var id: UUID
        var programDayID: UUID
        var ownerID: UUID?
        var exerciseID: UUID
        var position: Int
        var targetSets: Int
        var repMin: Int
        var repMax: Int
        var restSeconds: Int
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, programDayID: UUID, ownerID: UUID?, exerciseID: UUID, position: Int,
            targetSets: Int, repRange: ClosedRange<Int>, restSeconds: Int, updatedAt: Date
        ) {
            self.id = id
            self.programDayID = programDayID
            self.ownerID = ownerID
            self.exerciseID = exerciseID
            self.position = position
            self.targetSets = targetSets
            self.repMin = repRange.lowerBound
            self.repMax = repRange.upperBound
            self.restSeconds = restSeconds
            self.updatedAt = updatedAt
            self.needsPush = ownerID != nil
        }
    }

    /// The user's own weight step and rep range for one exercise.
    @Model
    final class ExerciseSetting {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var exerciseID: UUID
        var stepKg: Double
        var repMin: Int?
        var repMax: Int?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, exerciseID: UUID, stepKg: Double, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.exerciseID = exerciseID
            self.stepKg = stepKg
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class WorkoutSession {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var programDayID: UUID?
        var performedOn: String
        var startedAt: Date
        var endedAt: Date?
        var note: String?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, programDayID: UUID?, performedOn: Day, startedAt: Date, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.programDayID = programDayID
            self.performedOn = performedOn.isoString
            self.startedAt = startedAt
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    @Model
    final class WorkoutSet {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var sessionID: UUID
        var exerciseID: UUID
        var position: Int
        /// For a body-weight exercise only the added load, 0 for none.
        var weightKg: Double
        var reps: Int
        var rpe: Double?
        var isWarmup: Bool
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(
            id: UUID, userID: UUID, sessionID: UUID, exerciseID: UUID, position: Int,
            weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool, updatedAt: Date
        ) {
            self.id = id
            self.userID = userID
            self.sessionID = sessionID
            self.exerciseID = exerciseID
            self.position = position
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }

    /// Body weight in kg or a circumference in cm.
    @Model
    final class BodyMeasurement {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var measuredOn: String
        var kind: String
        var value: Double
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID, userID: UUID, measuredOn: Day, kind: String, value: Double, updatedAt: Date) {
            self.id = id
            self.userID = userID
            self.measuredOn = measuredOn.isoString
            self.kind = kind
            self.value = value
            self.updatedAt = updatedAt
            self.needsPush = true
        }
    }
}

extension Exercise {
    var name: LocalizedText {
        get { LocalizedText(json: nameJSON) }
        set { nameJSON = newValue.json }
    }

    var instructions: LocalizedText {
        get { LocalizedText(json: instructionsJSON) }
        set { instructionsJSON = newValue.json }
    }
}

extension Program {
    var name: LocalizedText {
        get { LocalizedText(json: nameJSON) }
        set { nameJSON = newValue.json }
    }
}

extension ProgramDay {
    var name: LocalizedText {
        get { LocalizedText(json: nameJSON) }
        set { nameJSON = newValue.json }
    }
}

extension WorkoutSet {
    /// Nil for a warm-up set: it does not count towards progression, records or volume.
    var workingSet: WorkingSet? {
        isWarmup ? nil : WorkingSet(weightKg: weightKg, reps: reps, rpe: rpe)
    }
}
