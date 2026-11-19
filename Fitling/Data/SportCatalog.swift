import Foundation
import SwiftData
import FitlingCore

/// The shared exercises and ready-made programmes, as `Resources/SportCatalog.json` holds them.
/// The same file seeds Supabase (`scripts/sport-seed.mjs`), so the ids on the device and on the
/// server are the same and a logged set can refer to a shared exercise.
struct SportCatalog: Decodable {
    struct ExerciseEntry: Decodable {
        let id: UUID
        let name: LocalizedText
        let instructions: LocalizedText
        let kind: String
        let loadType: String
        let equipment: String
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let defaultStepKg: Double
    }

    struct ProgramEntry: Decodable {
        let id: UUID
        let name: LocalizedText
        let daysPerWeek: Int
        let days: [DayEntry]
    }

    struct DayEntry: Decodable {
        let id: UUID
        let name: LocalizedText
        let position: Int
        let exercises: [ItemEntry]
    }

    struct ItemEntry: Decodable {
        let id: UUID
        let exerciseID: UUID
        let position: Int
        let targetSets: Int
        let repMin: Int
        let repMax: Int
        let restSeconds: Int
    }

    let version: Int
    let exercises: [ExerciseEntry]
    let programs: [ProgramEntry]

    static func bundled(in bundle: Bundle = .main) -> SportCatalog? {
        guard let url = bundle.url(forResource: "SportCatalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SportCatalog.self, from: data)
    }

    /// Puts the shared rows on the device, or brings them up to date. Cheap when nothing changed:
    /// the stored version and the number of shared exercises say whether there is work. Signing
    /// out erases the store, so the count catches a fresh start after that too.
    @MainActor
    func install(into context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) {
        let key = "fitling.sportCatalogVersion"
        let shared = (try? context.fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.ownerID == nil }))) ?? 0
        guard defaults.integer(forKey: key) < version else { _ = shared; return }

        let exercisesByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.id, $0) })
        for entry in exercises {
            let exercise = exercisesByID[entry.id] ?? {
                let made = Exercise(
                    id: entry.id, ownerID: nil, name: entry.name, kind: .compound, loadType: .external, equipment: entry.equipment,
                    primaryMuscles: [], secondaryMuscles: [], defaultStepKg: entry.defaultStepKg, updatedAt: now
                )
                context.insert(made)
                return made
            }()
            exercise.name = entry.name
            exercise.instructions = entry.instructions
            exercise.kind = entry.kind
            exercise.loadType = entry.loadType
            exercise.equipment = entry.equipment
            exercise.primaryMuscles = entry.primaryMuscles
            exercise.secondaryMuscles = entry.secondaryMuscles
            exercise.defaultStepKg = entry.defaultStepKg
            exercise.deletedAt = nil
            exercise.needsPush = false
        }

        let programsByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Program>())) ?? []).map { ($0.id, $0) })
        let daysByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<ProgramDay>())) ?? []).map { ($0.id, $0) })
        let itemsByID = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<ProgramExercise>())) ?? []).map { ($0.id, $0) })
        for entry in programs {
            let program = programsByID[entry.id] ?? {
                let made = Program(id: entry.id, ownerID: nil, name: entry.name, daysPerWeek: entry.daysPerWeek, updatedAt: now)
                context.insert(made)
                return made
            }()
            program.name = entry.name
            program.daysPerWeek = entry.daysPerWeek
            program.needsPush = false
            for dayEntry in entry.days {
                let day = daysByID[dayEntry.id] ?? {
                    let made = ProgramDay(id: dayEntry.id, programID: entry.id, ownerID: nil, name: dayEntry.name, position: dayEntry.position, updatedAt: now)
                    context.insert(made)
                    return made
                }()
                day.name = dayEntry.name
                day.position = dayEntry.position
                day.needsPush = false
                for itemEntry in dayEntry.exercises {
                    let item = itemsByID[itemEntry.id] ?? {
                        let made = ProgramExercise(
                            id: itemEntry.id, programDayID: dayEntry.id, ownerID: nil, exerciseID: itemEntry.exerciseID,
                            position: itemEntry.position, targetSets: itemEntry.targetSets,
                            repRange: itemEntry.repMin...itemEntry.repMax, restSeconds: itemEntry.restSeconds, updatedAt: now
                        )
                        context.insert(made)
                        return made
                    }()
                    item.exerciseID = itemEntry.exerciseID
                    item.position = itemEntry.position
                    item.targetSets = itemEntry.targetSets
                    item.repMin = itemEntry.repMin
                    item.repMax = itemEntry.repMax
                    item.restSeconds = itemEntry.restSeconds
                    item.needsPush = false
                }
            }
        }
        try? context.save()
        defaults.set(version, forKey: key)
    }
}
