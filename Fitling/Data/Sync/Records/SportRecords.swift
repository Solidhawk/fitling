import Foundation
import SwiftData
import FitlingCore

// The sport tables (TASKS 4.2). Each record writes every column itself: `synced_at` belongs to the
// server and is never sent, and an empty value goes as null instead of being left out.

// MARK: - exercises

struct ExerciseRecord: SyncRecord, Equatable {
    var id: UUID
    var ownerID: UUID?
    var name: LocalizedText
    var instructions: LocalizedText
    var kind: String
    var loadType: String
    var equipment: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var defaultStepKg: Double
    var imageURL: String?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, instructions, kind, equipment
        case ownerID = "owner_id"
        case loadType = "load_type"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case defaultStepKg = "default_step_kg"
        case imageURL = "image_url"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(name, forKey: .name)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(kind, forKey: .kind)
        try c.encode(loadType, forKey: .loadType)
        try c.encode(equipment, forKey: .equipment)
        try c.encode(primaryMuscles, forKey: .primaryMuscles)
        try c.encode(secondaryMuscles, forKey: .secondaryMuscles)
        try c.encode(defaultStepKg, forKey: .defaultStepKg)
        try c.encode(imageURL, forKey: .imageURL)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension Exercise: SyncableModel {
    static var tableName: String { "exercises" }
    static var keyColumn: String { "id" }
    /// Shared exercises come with the app (`SportCatalog`); only the user's own are pulled.
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<Exercise> {
        FetchDescriptor(predicate: #Predicate<Exercise> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<Exercise> {
        FetchDescriptor(predicate: #Predicate<Exercise> { ids.contains($0.id) })
    }

    static func make(from record: ExerciseRecord) -> Exercise {
        let exercise = Exercise(
            id: record.id, ownerID: record.ownerID, name: record.name, kind: .compound, loadType: .external,
            equipment: record.equipment, primaryMuscles: [], secondaryMuscles: [], defaultStepKg: record.defaultStepKg,
            updatedAt: record.updatedAt
        )
        exercise.apply(record)
        return exercise
    }

    var syncID: UUID { id }

    var record: ExerciseRecord {
        ExerciseRecord(
            id: id, ownerID: ownerID, name: name, instructions: instructions, kind: kind, loadType: loadType,
            equipment: equipment, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
            defaultStepKg: defaultStepKg, imageURL: imageURL, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ExerciseRecord) {
        ownerID = record.ownerID
        name = record.name
        instructions = record.instructions
        kind = record.kind
        loadType = record.loadType
        equipment = record.equipment
        primaryMuscles = record.primaryMuscles
        secondaryMuscles = record.secondaryMuscles
        defaultStepKg = record.defaultStepKg
        imageURL = record.imageURL
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - programs

struct ProgramRecord: SyncRecord, Equatable {
    var id: UUID
    var ownerID: UUID?
    var name: LocalizedText
    var daysPerWeek: Int
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case daysPerWeek = "days_per_week"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(name, forKey: .name)
        try c.encode(daysPerWeek, forKey: .daysPerWeek)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension Program: SyncableModel {
    static var tableName: String { "programs" }
    static var keyColumn: String { "id" }
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<Program> {
        FetchDescriptor(predicate: #Predicate<Program> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<Program> {
        FetchDescriptor(predicate: #Predicate<Program> { ids.contains($0.id) })
    }

    static func make(from record: ProgramRecord) -> Program {
        let program = Program(id: record.id, ownerID: record.ownerID, name: record.name, daysPerWeek: record.daysPerWeek, updatedAt: record.updatedAt)
        program.apply(record)
        return program
    }

    var syncID: UUID { id }

    var record: ProgramRecord {
        ProgramRecord(id: id, ownerID: ownerID, name: name, daysPerWeek: daysPerWeek, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil)
    }

    func apply(_ record: ProgramRecord) {
        ownerID = record.ownerID
        name = record.name
        daysPerWeek = record.daysPerWeek
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - program_days

struct ProgramDayRecord: SyncRecord, Equatable {
    var id: UUID
    var programID: UUID
    var ownerID: UUID?
    var name: LocalizedText
    var position: Int
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case programID = "program_id"
        case ownerID = "owner_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programID, forKey: .programID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(name, forKey: .name)
        try c.encode(position, forKey: .position)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ProgramDay: SyncableModel {
    static var tableName: String { "program_days" }
    static var keyColumn: String { "id" }
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<ProgramDay> {
        FetchDescriptor(predicate: #Predicate<ProgramDay> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ProgramDay> {
        FetchDescriptor(predicate: #Predicate<ProgramDay> { ids.contains($0.id) })
    }

    static func make(from record: ProgramDayRecord) -> ProgramDay {
        let day = ProgramDay(
            id: record.id, programID: record.programID, ownerID: record.ownerID, name: record.name,
            position: record.position, updatedAt: record.updatedAt
        )
        day.apply(record)
        return day
    }

    var syncID: UUID { id }

    var record: ProgramDayRecord {
        ProgramDayRecord(
            id: id, programID: programID, ownerID: ownerID, name: name, position: position,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ProgramDayRecord) {
        programID = record.programID
        ownerID = record.ownerID
        name = record.name
        position = record.position
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - program_exercises

struct ProgramExerciseRecord: SyncRecord, Equatable {
    var id: UUID
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
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, position
        case programDayID = "program_day_id"
        case ownerID = "owner_id"
        case exerciseID = "exercise_id"
        case targetSets = "target_sets"
        case repMin = "rep_min"
        case repMax = "rep_max"
        case restSeconds = "rest_seconds"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programDayID, forKey: .programDayID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(position, forKey: .position)
        try c.encode(targetSets, forKey: .targetSets)
        try c.encode(repMin, forKey: .repMin)
        try c.encode(repMax, forKey: .repMax)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ProgramExercise: SyncableModel {
    static var tableName: String { "program_exercises" }
    static var keyColumn: String { "id" }
    static var ownerColumn: String? { "owner_id" }

    static var pending: FetchDescriptor<ProgramExercise> {
        FetchDescriptor(predicate: #Predicate<ProgramExercise> { $0.needsPush && $0.ownerID != nil })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ProgramExercise> {
        FetchDescriptor(predicate: #Predicate<ProgramExercise> { ids.contains($0.id) })
    }

    static func make(from record: ProgramExerciseRecord) -> ProgramExercise {
        let item = ProgramExercise(
            id: record.id, programDayID: record.programDayID, ownerID: record.ownerID, exerciseID: record.exerciseID,
            position: record.position, targetSets: record.targetSets, repRange: record.repMin...max(record.repMin, record.repMax),
            restSeconds: record.restSeconds, updatedAt: record.updatedAt
        )
        item.apply(record)
        return item
    }

    var syncID: UUID { id }

    var record: ProgramExerciseRecord {
        ProgramExerciseRecord(
            id: id, programDayID: programDayID, ownerID: ownerID, exerciseID: exerciseID, position: position,
            targetSets: targetSets, repMin: repMin, repMax: repMax, restSeconds: restSeconds,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ProgramExerciseRecord) {
        programDayID = record.programDayID
        ownerID = record.ownerID
        exerciseID = record.exerciseID
        position = record.position
        targetSets = record.targetSets
        repMin = record.repMin
        repMax = record.repMax
        restSeconds = record.restSeconds
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - exercise_settings

struct ExerciseSettingRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var exerciseID: UUID
    var stepKg: Double
    var repMin: Int?
    var repMax: Int?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case exerciseID = "exercise_id"
        case stepKg = "step_kg"
        case repMin = "rep_min"
        case repMax = "rep_max"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(stepKg, forKey: .stepKg)
        try c.encode(repMin, forKey: .repMin)
        try c.encode(repMax, forKey: .repMax)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension ExerciseSetting: SyncableModel {
    static var tableName: String { "exercise_settings" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<ExerciseSetting> {
        FetchDescriptor(predicate: #Predicate<ExerciseSetting> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<ExerciseSetting> {
        FetchDescriptor(predicate: #Predicate<ExerciseSetting> { ids.contains($0.id) })
    }

    static func make(from record: ExerciseSettingRecord) -> ExerciseSetting {
        let setting = ExerciseSetting(id: record.id, userID: record.userID, exerciseID: record.exerciseID, stepKg: record.stepKg, updatedAt: record.updatedAt)
        setting.apply(record)
        return setting
    }

    var syncID: UUID { id }

    var record: ExerciseSettingRecord {
        ExerciseSettingRecord(
            id: id, userID: userID, exerciseID: exerciseID, stepKg: stepKg, repMin: repMin, repMax: repMax,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: ExerciseSettingRecord) {
        userID = record.userID
        exerciseID = record.exerciseID
        stepKg = record.stepKg
        repMin = record.repMin
        repMax = record.repMax
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - workout_sessions

struct WorkoutSessionRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var programDayID: UUID?
    var performedOn: Day
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note
        case userID = "user_id"
        case programDayID = "program_day_id"
        case performedOn = "performed_on"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(programDayID, forKey: .programDayID)
        try c.encode(performedOn, forKey: .performedOn)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(note, forKey: .note)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension WorkoutSession: SyncableModel {
    static var tableName: String { "workout_sessions" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<WorkoutSession> {
        FetchDescriptor(predicate: #Predicate<WorkoutSession> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<WorkoutSession> {
        FetchDescriptor(predicate: #Predicate<WorkoutSession> { ids.contains($0.id) })
    }

    static func make(from record: WorkoutSessionRecord) -> WorkoutSession {
        let session = WorkoutSession(
            id: record.id, userID: record.userID, programDayID: record.programDayID, performedOn: record.performedOn,
            startedAt: record.startedAt, updatedAt: record.updatedAt
        )
        session.apply(record)
        return session
    }

    var syncID: UUID { id }

    var record: WorkoutSessionRecord {
        WorkoutSessionRecord(
            id: id, userID: userID, programDayID: programDayID, performedOn: Day(isoString: performedOn) ?? Day(ordinal: 0),
            startedAt: startedAt, endedAt: endedAt, note: note, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: WorkoutSessionRecord) {
        userID = record.userID
        programDayID = record.programDayID
        performedOn = record.performedOn.isoString
        startedAt = record.startedAt
        endedAt = record.endedAt
        note = record.note
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - workout_sets

struct WorkoutSetRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var position: Int
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, position, reps, rpe
        case userID = "user_id"
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case weightKg = "weight_kg"
        case isWarmup = "is_warmup"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(exerciseID, forKey: .exerciseID)
        try c.encode(position, forKey: .position)
        try c.encode(weightKg, forKey: .weightKg)
        try c.encode(reps, forKey: .reps)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(isWarmup, forKey: .isWarmup)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension WorkoutSet: SyncableModel {
    static var tableName: String { "workout_sets" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<WorkoutSet> {
        FetchDescriptor(predicate: #Predicate<WorkoutSet> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<WorkoutSet> {
        FetchDescriptor(predicate: #Predicate<WorkoutSet> { ids.contains($0.id) })
    }

    static func make(from record: WorkoutSetRecord) -> WorkoutSet {
        let set = WorkoutSet(
            id: record.id, userID: record.userID, sessionID: record.sessionID, exerciseID: record.exerciseID,
            position: record.position, weightKg: record.weightKg, reps: record.reps, rpe: record.rpe,
            isWarmup: record.isWarmup, updatedAt: record.updatedAt
        )
        set.apply(record)
        return set
    }

    var syncID: UUID { id }

    var record: WorkoutSetRecord {
        WorkoutSetRecord(
            id: id, userID: userID, sessionID: sessionID, exerciseID: exerciseID, position: position, weightKg: weightKg,
            reps: reps, rpe: rpe, isWarmup: isWarmup, updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: WorkoutSetRecord) {
        userID = record.userID
        sessionID = record.sessionID
        exerciseID = record.exerciseID
        position = record.position
        weightKg = record.weightKg
        reps = record.reps
        rpe = record.rpe
        isWarmup = record.isWarmup
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}

// MARK: - body_measurements

struct BodyMeasurementRecord: SyncRecord, Equatable {
    var id: UUID
    var userID: UUID
    var measuredOn: Day
    var kind: String
    var value: Double
    var updatedAt: Date
    var deletedAt: Date?
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, value
        case userID = "user_id"
        case measuredOn = "measured_on"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(measuredOn, forKey: .measuredOn)
        try c.encode(kind, forKey: .kind)
        try c.encode(value, forKey: .value)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

extension BodyMeasurement: SyncableModel {
    static var tableName: String { "body_measurements" }
    static var keyColumn: String { "id" }

    static var pending: FetchDescriptor<BodyMeasurement> {
        FetchDescriptor(predicate: #Predicate<BodyMeasurement> { $0.needsPush })
    }

    static func matching(ids: [UUID]) -> FetchDescriptor<BodyMeasurement> {
        FetchDescriptor(predicate: #Predicate<BodyMeasurement> { ids.contains($0.id) })
    }

    static func make(from record: BodyMeasurementRecord) -> BodyMeasurement {
        let measurement = BodyMeasurement(
            id: record.id, userID: record.userID, measuredOn: record.measuredOn, kind: record.kind,
            value: record.value, updatedAt: record.updatedAt
        )
        measurement.apply(record)
        return measurement
    }

    var syncID: UUID { id }

    var record: BodyMeasurementRecord {
        BodyMeasurementRecord(
            id: id, userID: userID, measuredOn: Day(isoString: measuredOn) ?? Day(ordinal: 0), kind: kind, value: value,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func apply(_ record: BodyMeasurementRecord) {
        userID = record.userID
        measuredOn = record.measuredOn.isoString
        kind = record.kind
        value = record.value
        updatedAt = record.updatedAt
        deletedAt = record.deletedAt
        needsPush = false
    }
}
