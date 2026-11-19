import Foundation
import SwiftData

/// A local model that syncs with one table. Each model writes its own fetch descriptors: a
/// predicate over a generic model type is not something SwiftData is known to translate.
protocol SyncableModel: PersistentModel {
    associatedtype Record: SyncRecord

    static var tableName: String { get }
    /// The column that tells rows apart on the server.
    static var keyColumn: String { get }
    /// Set for tables that also hold shared rows (`owner_id` is null): only the user's own rows
    /// are pulled; shared rows reach the device another way (a lookup or a search).
    static var ownerColumn: String? { get }
    /// The rows the server has not seen yet.
    static var pending: FetchDescriptor<Self> { get }
    static func matching(ids: [UUID]) -> FetchDescriptor<Self>
    /// A new local row for a record this device has never seen.
    static func make(from record: Record) -> Self

    var syncID: UUID { get }
    var updatedAt: Date { get set }
    var needsPush: Bool { get set }
    var deletedAt: Date? { get }
    var record: Record { get }
    /// Takes over the server's version.
    func apply(_ record: Record)
}

extension SyncableModel {
    static var ownerColumn: String? { nil }
}

/// One table in a sync round. The engine walks a list of these in the order of ARCHITECTURE §3.5.
@MainActor
protocol SyncTable {
    func push(with engine: SyncEngine) async throws
    func pull(with engine: SyncEngine) async throws
    func hasPendingRows(in context: ModelContext) -> Bool
}

/// The tables that sync, parents before children (ARCHITECTURE §3.5). Later phases add theirs here.
@MainActor
enum SyncTables {
    static var all: [any SyncTable] {
        [
            ModelTable<UserProfile>(), ModelTable<TargetPeriod>(),
            ModelTable<Product>(), ModelTable<Recipe>(), ModelTable<RecipeIngredient>(), ModelTable<FoodEntry>(), ModelTable<WaterEntry>(), ModelTable<FavoriteProduct>(),
            ModelTable<Creature>(),
            ModelTable<Exercise>(), ModelTable<Program>(), ModelTable<ProgramDay>(), ModelTable<ProgramExercise>(),
            ModelTable<ExerciseSetting>(), ModelTable<WorkoutSession>(), ModelTable<WorkoutSet>(), ModelTable<BodyMeasurement>(),
            ModelTable<MenuPreferences>(), ModelTable<ExcludedIngredient>(), ModelTable<MealPlanEntry>(),
            ModelTable<ShoppingList>(), ModelTable<ShoppingItem>(), ModelTable<FavoriteSupermarket>(),
        ]
    }
}

struct ModelTable<Model: SyncableModel>: SyncTable {
    func hasPendingRows(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(Model.pending)) ?? 0) > 0
    }

    func push(with engine: SyncEngine) async throws {
        try await engine.push(Model.self)
    }

    func pull(with engine: SyncEngine) async throws {
        try await engine.pull(Model.self)
    }
}
