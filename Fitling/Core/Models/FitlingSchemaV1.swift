import Foundation
import SwiftData

/// The local database. Every model that syncs has the same columns as its table in
/// `supabase/schema.sql`; `scripts/check-models.mjs` keeps the two in step.
///
/// Rules that hold for every model, and why:
/// - Other rows are referred to by their id, not with `@Relationship`. A child can arrive from
///   the server before its parent, and a relationship would then have nothing to point at.
/// - Enums are stored as their raw string. `#Predicate` can filter on a string, and a value a
///   newer app version wrote does not crash an older one.
/// - A calendar day is stored as "2026-11-18", the same as a Postgres `date`. It sorts
///   correctly as text and has no time zone to get wrong.
/// - `needsPush` marks a row the server has not seen yet. `deletedAt` marks a deleted row; the
///   row stays until the server has it, otherwise the deletion could never sync.
enum FitlingSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self, TargetPeriod.self,
            Product.self, FoodEntry.self, WaterEntry.self, FavoriteProduct.self,
            Creature.self,
            Exercise.self, Program.self, ProgramDay.self, ProgramExercise.self, ExerciseSetting.self,
            WorkoutSession.self, WorkoutSet.self, BodyMeasurement.self,
            Recipe.self, RecipeIngredient.self, MenuPreferences.self, ExcludedIngredient.self, MealPlanEntry.self,
            ShoppingList.self, ShoppingListMember.self, ShoppingItem.self,
            Supermarket.self, Offer.self, FavoriteSupermarket.self,
            ProgressPhoto.self, DayActivity.self, SyncCursor.self,
        ]
    }
}

enum FitlingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FitlingSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

func makeModelContainer(inMemory: Bool) throws -> ModelContainer {
    try ModelContainer(
        for: Schema(versionedSchema: FitlingSchemaV1.self),
        migrationPlan: FitlingMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
    )
}

typealias UserProfile = FitlingSchemaV1.UserProfile
typealias TargetPeriod = FitlingSchemaV1.TargetPeriod
typealias Product = FitlingSchemaV1.Product
typealias FoodEntry = FitlingSchemaV1.FoodEntry
typealias WaterEntry = FitlingSchemaV1.WaterEntry
typealias FavoriteProduct = FitlingSchemaV1.FavoriteProduct
typealias Creature = FitlingSchemaV1.Creature
typealias Exercise = FitlingSchemaV1.Exercise
typealias Program = FitlingSchemaV1.Program
typealias ProgramDay = FitlingSchemaV1.ProgramDay
typealias ProgramExercise = FitlingSchemaV1.ProgramExercise
typealias ExerciseSetting = FitlingSchemaV1.ExerciseSetting
typealias WorkoutSession = FitlingSchemaV1.WorkoutSession
typealias WorkoutSet = FitlingSchemaV1.WorkoutSet
typealias BodyMeasurement = FitlingSchemaV1.BodyMeasurement
typealias Recipe = FitlingSchemaV1.Recipe
typealias RecipeIngredient = FitlingSchemaV1.RecipeIngredient
typealias MenuPreferences = FitlingSchemaV1.MenuPreferences
typealias ExcludedIngredient = FitlingSchemaV1.ExcludedIngredient
typealias MealPlanEntry = FitlingSchemaV1.MealPlanEntry
typealias ShoppingList = FitlingSchemaV1.ShoppingList
typealias ShoppingListMember = FitlingSchemaV1.ShoppingListMember
typealias ShoppingItem = FitlingSchemaV1.ShoppingItem
typealias Supermarket = FitlingSchemaV1.Supermarket
typealias Offer = FitlingSchemaV1.Offer
typealias FavoriteSupermarket = FitlingSchemaV1.FavoriteSupermarket
typealias ProgressPhoto = FitlingSchemaV1.ProgressPhoto
typealias DayActivity = FitlingSchemaV1.DayActivity
typealias SyncCursor = FitlingSchemaV1.SyncCursor
