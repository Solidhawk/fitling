import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// Every value is saved in one context and read back in another, so it really went through the store.
@MainActor
@Suite struct ModelStoreTests {
    let userID = UUID()
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let today = Day(ordinal: 20775)

    func reread<Model: PersistentModel>(_ type: Model.Type, from container: ModelContainer) throws -> [Model] {
        try ModelContext(container).fetch(FetchDescriptor<Model>())
    }

    func save(_ models: [any PersistentModel], in container: ModelContainer) throws {
        let context = ModelContext(container)
        for model in models {
            context.insert(model)
        }
        try context.save()
    }

    @Test func storeHoldsEveryModelOfTheSchema() throws {
        let container = try makeModelContainer(inMemory: true)
        #expect(FitlingSchemaV1.models.count == 29)
        #expect(container.schema.entities.count == 29)
    }

    @Test func profileGivesBackTheBodyAndTargetsItWasMadeFrom() throws {
        let container = try makeModelContainer(inMemory: true)
        let body = BodyProfile(
            birthDay: Day(ordinal: 9505), sex: .female, heightCm: 165.5, weightKg: 65.2, activityLevel: .veryActive, goal: .buildMuscle
        )
        let targets = NutritionTargets(kcal: 2400, proteinG: 117, carbsG: 320, fatG: 67)
        try save([
            UserProfile(id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body, targets: targets, targetsAreManual: false, updatedAt: now),
        ], in: container)

        let stored = try #require(reread(UserProfile.self, from: container).first)
        #expect(stored.bodyProfile == body)
        #expect(stored.targets == targets)
        #expect(stored.birthDate == "1996-01-10")
        #expect(stored.activityLevel == "very_active")
        #expect(stored.needsPush)
    }

    @Test func profileWithAnUnknownValueHasNoBodyProfile() throws {
        let body = BodyProfile(birthDay: Day(ordinal: 9505), sex: .male, heightCm: 180, weightKg: 80, activityLevel: .light, goal: .lose)
        let targets = NutritionTargets(kcal: 2000, proteinG: 160, carbsG: 200, fatG: 56)
        let profile = UserProfile(id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body, targets: targets, targetsAreManual: false, updatedAt: now)
        profile.goal = "een doel uit een nieuwere versie"
        #expect(profile.bodyProfile == nil)
    }

    @Test func productKeepsItsNamesPerLanguageAndItsUnknownValues() throws {
        let container = try makeModelContainer(inMemory: true)
        let name = LocalizedText(["nl": "Pindakaas", "en": "Peanut butter"])
        let product = Product(id: UUID(), ownerID: nil, source: "off", name: name, quantityUnit: "g", updatedAt: now)
        product.gtin = "4006381333931"
        product.kcal100 = 600
        try save([product], in: container)

        let stored = try #require(reread(Product.self, from: container).first)
        #expect(stored.name == name)
        #expect(stored.gtin == "4006381333931")
        #expect(stored.kcal100 == 600)
        #expect(stored.protein100 == nil)
        #expect(stored.deletedAt == nil)
    }

    @Test func onlyTheUsersOwnProductsAreMarkedForPush() {
        let name = LocalizedText(["nl": "Soep"])
        #expect(Product(id: UUID(), ownerID: nil, source: "off", name: name, quantityUnit: "g", updatedAt: now).needsPush == false)
        #expect(Product(id: UUID(), ownerID: userID, source: "user", name: name, quantityUnit: "ml", updatedAt: now).needsPush)
    }

    @Test func foodEntryKeepsTheDayAsAPlainDate() throws {
        let container = try makeModelContainer(inMemory: true)
        let entry = FoodEntry(
            id: UUID(), userID: userID, consumedOn: today, meal: .lunch, name: "Pindakaas",
            quantity: 30, quantityUnit: "g", kcal: 180, updatedAt: now
        )
        entry.proteinG = 7.5
        try save([entry], in: container)

        let stored = try #require(reread(FoodEntry.self, from: container).first)
        #expect(stored.consumedOn == "2026-11-18")
        #expect(stored.meal == "lunch")
        #expect(stored.proteinG == 7.5)
        #expect(stored.carbsG == nil)
    }

    @Test func creatureGivesBackTheEngineState() throws {
        let container = try makeModelContainer(inMemory: true)
        var state = CreatureState(species: .mole, colorIndex: 2, tone: .coach, createdOn: today.adding(-10))
        let creature = Creature(userID: userID, name: "Vonk", state: state, updatedAt: now)
        try save([creature], in: container)
        let stored = try #require(reread(Creature.self, from: container).first)
        #expect(stored.state == state)

        state.bodyShape = 0.45
        state.xp = 320
        state.lastProcessedDay = today.adding(-1)
        state.offTargetDays = 2
        creature.apply(state, at: now.addingTimeInterval(60))
        #expect(creature.state == state)
        #expect(creature.updatedAt == now.addingTimeInterval(60))
        #expect(creature.name == "Vonk")
    }

    @Test func exerciseKeepsItsMusclesAndTexts() throws {
        let container = try makeModelContainer(inMemory: true)
        let exercise = Exercise(
            id: UUID(), ownerID: nil, name: LocalizedText(["nl": "Bankdrukken"]), kind: .compound, loadType: .external,
            equipment: "barbell", primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], defaultStepKg: 2.5, updatedAt: now
        )
        exercise.instructions = LocalizedText(["nl": "Schouderbladen naar elkaar."])
        try save([exercise], in: container)

        let stored = try #require(reread(Exercise.self, from: container).first)
        #expect(stored.name == LocalizedText(["nl": "Bankdrukken"]))
        #expect(stored.instructions == LocalizedText(["nl": "Schouderbladen naar elkaar."]))
        #expect(stored.primaryMuscles == ["chest"])
        #expect(stored.secondaryMuscles == ["triceps", "shoulders"])
        #expect(stored.kind == "compound")
    }

    @Test func warmUpSetsAreNotWorkingSets() {
        let warmUp = WorkoutSet(
            id: UUID(), userID: userID, sessionID: UUID(), exerciseID: UUID(), position: 0,
            weightKg: 40, reps: 10, rpe: nil, isWarmup: true, updatedAt: now
        )
        let working = WorkoutSet(
            id: UUID(), userID: userID, sessionID: UUID(), exerciseID: UUID(), position: 1,
            weightKg: 60, reps: 8, rpe: 7.5, isWarmup: false, updatedAt: now
        )
        #expect(warmUp.workingSet == nil)
        #expect(working.workingSet == WorkingSet(weightKg: 60, reps: 8, rpe: 7.5))
    }

    @Test func recipeBecomesAPlannerRecipe() throws {
        let container = try makeModelContainer(inMemory: true)
        let recipe = Recipe(
            id: UUID(), ownerID: nil, title: LocalizedText(["nl": "Chili"]), servings: 4, cookMinutes: 35,
            kcalPerServing: 620, proteinGPerServing: 41, carbsGPerServing: 60, fatGPerServing: 22,
            mealSlots: [.dinner, .lunch], updatedAt: now
        )
        recipe.steps = ["nl": ["Snijd de ui.", "Bak hem glazig."]]
        recipe.tags = ["meat"]
        recipe.keepsWell = true
        recipe.costCentsPerServing = 240
        try save([recipe], in: container)

        let stored = try #require(reread(Recipe.self, from: container).first)
        #expect(stored.steps == ["nl": ["Snijd de ui.", "Bak hem glazig."]])
        let ingredient = UUID()
        #expect(stored.plannerRecipe(ingredientIDs: [ingredient]) == PlannerRecipe(
            id: recipe.id, kcalPerServing: 620, proteinPerServing: 41, cookMinutes: 35, costCentsPerServing: 240,
            slots: [.dinner, .lunch], tags: ["meat"], ingredientIDs: [ingredient], keepsWell: true
        ))
    }

    @Test func recipeWithoutEnergyIsLeftOutOfThePlanner() {
        let recipe = Recipe(
            id: UUID(), ownerID: userID, title: LocalizedText(["nl": "Thee"]), servings: 1, cookMinutes: 5,
            kcalPerServing: 0, proteinGPerServing: 0, carbsGPerServing: 0, fatGPerServing: 0, mealSlots: [.snack], updatedAt: now
        )
        #expect(recipe.plannerRecipe(ingredientIDs: []) == nil)
    }

    @Test func mealPlanEntryGivesBackThePlannedMeal() throws {
        let container = try makeModelContainer(inMemory: true)
        let meal = PlannedMeal(day: today, slot: .dinner, recipeID: UUID(), servings: 1.25, isLeftover: true, isPinned: false)
        try save([MealPlanEntry(id: UUID(), userID: userID, meal: meal, updatedAt: now)], in: container)

        let stored = try #require(reread(MealPlanEntry.self, from: container).first)
        #expect(stored.plannedMeal == meal)
        #expect(stored.loggedEntryID == nil)
    }

    @Test func listMemberIsUniquePerListAndUser() {
        let listID = UUID()
        let member = ShoppingListMember(listID: listID, userID: userID, role: "owner", displayName: "Anne", joinedAt: now)
        #expect(member.key == "\(listID.uuidString)|\(userID.uuidString)")
    }

    @Test func localOnlyModelsAreStored() throws {
        let container = try makeModelContainer(inMemory: true)
        try save([
            ProgressPhoto(id: UUID(), takenOn: today, fileName: "voor.jpg"),
            DayActivity(day: today, workoutKcal: 412, updatedAt: now),
            SyncCursor(table: "food_entries", syncedAt: now, pulledAt: now.addingTimeInterval(60)),
            SyncCursor(table: "water_entries", syncedAt: nil, pulledAt: now),
        ], in: container)

        #expect(try reread(ProgressPhoto.self, from: container).first?.takenOn == "2026-11-18")
        #expect(try reread(DayActivity.self, from: container).first?.workoutKcal == 412)
        let cursors = try reread(SyncCursor.self, from: container).sorted { $0.table < $1.table }
        #expect(cursors.map(\.table) == ["food_entries", "water_entries"])
        #expect(cursors.map(\.syncedAt) == [now, nil])
        #expect(cursors.first?.pulledAt == now.addingTimeInterval(60))
    }
}
