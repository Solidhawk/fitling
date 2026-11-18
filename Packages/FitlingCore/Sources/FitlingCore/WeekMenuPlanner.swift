import Foundation

/// Picks recipes per day: greedy per meal, then a correction per day. See docs/ARCHITECTURE.md
/// for why this beats an exact optimisation here.
public enum WeekMenuPlanner {
    /// A day counts as solved inside this share around the kcal target.
    public static let kcalTolerance = 0.05
    public static let servingStep = 0.25
    public static let servingRange: ClosedRange<Double> = 0.5...2.0
    /// A recipe appears on at most this many days in one plan.
    public static let maxUsesPerRecipe = 2

    /// The share of the day's energy per meal; scaled to the slots that are planned.
    static let slotShares: [MealSlot: Double] = [.breakfast: 0.25, .lunch: 0.30, .dinner: 0.35, .snack: 0.10]

    public static func plan(_ request: MenuRequest, recipes: [PlannerRecipe]) -> MenuPlan {
        guard !request.days.isEmpty, !request.slots.isEmpty, request.kcalTarget > 0 else {
            return MenuPlan(meals: [], issues: [])
        }
        var planner = Planner(request: request, recipes: recipes)
        return planner.run()
    }
}

private struct Planner {
    let request: MenuRequest
    let days: [Day]
    let slots: [MealSlot]
    let byID: [UUID: PlannerRecipe]
    let candidates: [MealSlot: [PlannerRecipe]]
    let shares: [MealSlot: Double]
    var uses: [UUID: Int] = [:]
    var meals: [PlannedMeal] = []

    init(request: MenuRequest, recipes: [PlannerRecipe]) {
        let slots = MealSlot.allCases.filter { request.slots.contains($0) }
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Sorted, so the plan does not depend on the order in which recipes arrive.
        let allowed = byID.values
            .filter { recipe in
                recipe.kcalPerServing > 0
                    && recipe.tags.isDisjoint(with: request.excludedTags)
                    && recipe.ingredientIDs.isDisjoint(with: request.excludedIngredientIDs)
                    && recipe.cookMinutes <= (request.maxCookMinutes ?? .max)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var bySlot: [MealSlot: [PlannerRecipe]] = [:]
        for slot in slots {
            bySlot[slot] = allowed.filter { $0.slots.contains(slot) }
        }

        let total = slots.reduce(0) { $0 + (WeekMenuPlanner.slotShares[$1] ?? 0) }
        var scaled: [MealSlot: Double] = [:]
        for slot in slots {
            scaled[slot] = (WeekMenuPlanner.slotShares[slot] ?? 0) / total
        }
        self.request = request
        self.days = Array(Set(request.days)).sorted()
        self.slots = slots
        self.byID = byID
        self.candidates = bySlot
        self.shares = scaled
    }

    mutating func run() -> MenuPlan {
        var issues: [MenuIssue] = []
        let pinned = request.pinned.filter { days.contains($0.day) && slots.contains($0.slot) && byID[$0.recipeID] != nil }
        for meal in pinned {
            uses[meal.recipeID, default: 0] += 1
        }

        for slot in slots where (candidates[slot] ?? []).isEmpty {
            let everyDayPinned = days.allSatisfy { day in pinned.contains { $0.day == day && $0.slot == slot } }
            if !everyDayPinned { issues.append(.noRecipes(slot: slot)) }
        }

        // Largest meal first: it leaves the least room to correct afterwards.
        let order = slots.sorted { (shares[$0] ?? 0, $1.rawValue) > (shares[$1] ?? 0, $0.rawValue) }
        for day in days {
            var today: [PlannedMeal] = []
            for slot in order {
                if var fixed = pinned.first(where: { $0.day == day && $0.slot == slot }) {
                    fixed.isPinned = true
                    today.append(fixed)
                } else if let reheated = leftover(for: day, slot: slot) {
                    uses[reheated.recipeID, default: 0] += 1
                    today.append(reheated)
                } else if let recipe = pick(for: day, slot: slot, taken: today, pinned: pinned) {
                    uses[recipe.id, default: 0] += 1
                    today.append(PlannedMeal(day: day, slot: slot, recipeID: recipe.id, servings: fittedServings(recipe, slot: slot)))
                }
            }
            refit(&today)
            raiseProtein(&today)
            meals += today
        }

        repairBudget()

        meals.sort { ($0.day, Self.slotIndex($0.slot)) < ($1.day, Self.slotIndex($1.slot)) }
        for day in days {
            let dayMeals = meals.filter { $0.day == day }
            let dayKcal = kcal(dayMeals)
            if !isWithinKcal(dayKcal) {
                issues.append(.kcalOutOfRange(day: day, kcal: Int(dayKcal.rounded())))
            }
            let missing = Double(request.proteinTargetG) - protein(dayMeals)
            if missing > 1e-9 {
                issues.append(.proteinShort(day: day, missingG: Int(missing.rounded(.up))))
            }
        }
        if let budget = request.budgetCents, cost(meals) > Double(budget) {
            issues.append(.overBudget(byCents: Int((cost(meals) - Double(budget)).rounded(.up))))
        }
        return MenuPlan(meals: meals, issues: issues)
    }

    // MARK: Choosing

    /// Yesterday's cooked dinner again, when meal prep is on and the recipe keeps well.
    private func leftover(for day: Day, slot: MealSlot) -> PlannedMeal? {
        guard request.mealPrep, slot == .dinner,
              let cooked = meals.first(where: { $0.day == day.adding(-1) && $0.slot == slot }),
              !cooked.isLeftover, byID[cooked.recipeID]?.keepsWell == true else { return nil }
        return PlannedMeal(day: day, slot: slot, recipeID: cooked.recipeID, servings: cooked.servings, isLeftover: true)
    }

    private func pick(for day: Day, slot: MealSlot, taken: [PlannedMeal], pinned: [PlannedMeal]) -> PlannerRecipe? {
        let available = (candidates[slot] ?? []).filter { recipe in !taken.contains { $0.recipeID == recipe.id } }
        let fresh = available.filter { (uses[$0.id] ?? 0) < WeekMenuPlanner.maxUsesPerRecipe }
        // With too few recipes a repeat is better than an empty plate.
        let pool = fresh.isEmpty ? available : fresh
        let cooksForTwo = request.mealPrep && slot == .dinner && days.contains(day.adding(1))
            && !pinned.contains { $0.day == day.adding(1) && $0.slot == slot }
        return pool.min { score($0, day: day, slot: slot, cooksForTwo: cooksForTwo) < score($1, day: day, slot: slot, cooksForTwo: cooksForTwo) }
    }

    /// Lower is better. Every part is a share, so the parts can be weighed against each other.
    private func score(_ recipe: PlannerRecipe, day: Day, slot: MealSlot, cooksForTwo: Bool) -> Double {
        let share = shares[slot] ?? 0
        let slotKcal = Double(request.kcalTarget) * share
        let slotProtein = max(Double(request.proteinTargetG) * share, 1)
        let servings = fittedServings(recipe, slot: slot)

        var total = abs(servings * recipe.kcalPerServing - slotKcal) / slotKcal
        total += 1.5 * max(0, slotProtein - servings * recipe.proteinPerServing) / slotProtein
        if (uses[recipe.id] ?? 0) > 0 { total += 0.3 }
        if cooksForTwo, !recipe.keepsWell { total += 0.5 }
        if let budget = request.budgetCents, let cents = recipe.costCentsPerServing {
            let mealBudget = max(Double(budget) * share / Double(days.count), 1)
            total += 0.5 * servings * Double(cents) / mealBudget
        }
        return total + 0.2 * jitter(day: day, slot: slot, recipe: recipe.id)
    }

    private func fittedServings(_ recipe: PlannerRecipe, slot: MealSlot) -> Double {
        let wanted = Double(request.kcalTarget) * (shares[slot] ?? 0) / recipe.kcalPerServing
        let stepped = (wanted / WeekMenuPlanner.servingStep).rounded() * WeekMenuPlanner.servingStep
        return min(max(stepped, WeekMenuPlanner.servingRange.lowerBound), WeekMenuPlanner.servingRange.upperBound)
    }

    // MARK: Correcting a day

    /// Moves servings one step at a time, always the step that brings the day closest to the target.
    private func refit(_ dayMeals: inout [PlannedMeal]) {
        let target = Double(request.kcalTarget)
        for _ in 0..<64 {
            let error = kcal(dayMeals) - target
            if abs(error) <= target * WeekMenuPlanner.kcalTolerance { return }
            var best: (index: Int, servings: Double, error: Double)?
            for (index, meal) in dayMeals.enumerated() where !meal.isPinned {
                guard let recipe = byID[meal.recipeID] else { continue }
                let servings = meal.servings + (error > 0 ? -WeekMenuPlanner.servingStep : WeekMenuPlanner.servingStep)
                guard WeekMenuPlanner.servingRange.contains(servings) else { continue }
                let newError = abs(error + (servings - meal.servings) * recipe.kcalPerServing)
                if newError < abs(error), newError < (best?.error ?? .infinity) {
                    best = (index, servings, newError)
                }
            }
            guard let best else { return }
            dayMeals[best.index].servings = best.servings
        }
    }

    /// First a larger portion of what is already planned, then a swap for a recipe with more protein.
    private mutating func raiseProtein(_ dayMeals: inout [PlannedMeal]) {
        let target = Double(request.proteinTargetG)
        let ceiling = Double(request.kcalTarget) * (1 + WeekMenuPlanner.kcalTolerance)

        var moved = true
        while moved, protein(dayMeals) < target {
            moved = false
            let byProtein = dayMeals.indices
                .filter { !dayMeals[$0].isPinned }
                .sorted { density(dayMeals[$0].recipeID) > density(dayMeals[$1].recipeID) }
            for index in byProtein {
                guard let recipe = byID[dayMeals[index].recipeID] else { continue }
                let servings = dayMeals[index].servings + WeekMenuPlanner.servingStep
                guard WeekMenuPlanner.servingRange.contains(servings),
                      kcal(dayMeals) + WeekMenuPlanner.servingStep * recipe.kcalPerServing <= ceiling else { continue }
                dayMeals[index].servings = servings
                moved = true
                break
            }
        }

        for _ in dayMeals.indices where protein(dayMeals) < target {
            var best: (meals: [PlannedMeal], protein: Double, old: UUID, new: UUID)?
            for (index, meal) in dayMeals.enumerated() where !meal.isPinned && !meal.isLeftover {
                for candidate in candidates[meal.slot] ?? [] where density(candidate.id) > density(meal.recipeID) {
                    guard (uses[candidate.id] ?? 0) < WeekMenuPlanner.maxUsesPerRecipe,
                          !dayMeals.contains(where: { $0.recipeID == candidate.id }) else { continue }
                    var trial = dayMeals
                    trial[index].recipeID = candidate.id
                    trial[index].servings = fittedServings(candidate, slot: meal.slot)
                    refit(&trial)
                    guard isWithinKcal(kcal(trial)) || !isWithinKcal(kcal(dayMeals)) else { continue }
                    let gained = protein(trial)
                    if gained > (best?.protein ?? protein(dayMeals)) {
                        best = (trial, gained, meal.recipeID, candidate.id)
                    }
                }
            }
            guard let best else { return }
            uses[best.old, default: 1] -= 1
            uses[best.new, default: 0] += 1
            dayMeals = best.meals
        }
    }

    // MARK: Budget

    /// Replaces the swap that saves most, as long as the days involved stay as good as they were.
    private mutating func repairBudget() {
        guard let budget = request.budgetCents else { return }
        for _ in 0..<(meals.count * 2) {
            let total = cost(meals)
            if total <= Double(budget) { return }
            var best: (meals: [PlannedMeal], saving: Double, old: UUID, new: UUID, count: Int)?

            for (index, meal) in meals.enumerated() where !meal.isPinned && !meal.isLeftover {
                // A cooked dinner and its leftover change together.
                var group = [index]
                if let reheated = meals.firstIndex(where: {
                    $0.isLeftover && $0.slot == meal.slot && $0.day == meal.day.adding(1) && $0.recipeID == meal.recipeID
                }) {
                    group.append(reheated)
                }
                let affectedDays = group.map { meals[$0].day }

                for candidate in candidates[meal.slot] ?? [] where candidate.id != meal.recipeID {
                    guard (uses[candidate.id] ?? 0) + group.count <= WeekMenuPlanner.maxUsesPerRecipe,
                          group.count == 1 || candidate.keepsWell,
                          !meals.contains(where: { affectedDays.contains($0.day) && $0.recipeID == candidate.id }) else { continue }
                    var trial = meals
                    for member in group {
                        trial[member].recipeID = candidate.id
                        trial[member].servings = fittedServings(candidate, slot: meal.slot)
                    }
                    var acceptable = true
                    for day in affectedDays {
                        let before = meals.filter { $0.day == day }
                        var after = trial.filter { $0.day == day }
                        refit(&after)
                        let keepsKcal = isWithinKcal(kcal(after)) || !isWithinKcal(kcal(before))
                        let keepsProtein = protein(after) >= Double(request.proteinTargetG) || protein(after) >= protein(before)
                        guard keepsKcal, keepsProtein else {
                            acceptable = false
                            break
                        }
                        trial.removeAll { $0.day == day }
                        trial += after
                    }
                    guard acceptable else { continue }
                    let saving = total - cost(trial)
                    if saving > (best?.saving ?? 0.5) {
                        best = (trial, saving, meal.recipeID, candidate.id, group.count)
                    }
                }
            }

            guard let best else { return }
            uses[best.old, default: best.count] -= best.count
            uses[best.new, default: 0] += best.count
            meals = best.meals
        }
    }

    // MARK: Sums

    private func kcal(_ meals: [PlannedMeal]) -> Double {
        meals.reduce(0) { $0 + $1.servings * (byID[$1.recipeID]?.kcalPerServing ?? 0) }
    }

    private func protein(_ meals: [PlannedMeal]) -> Double {
        meals.reduce(0) { $0 + $1.servings * (byID[$1.recipeID]?.proteinPerServing ?? 0) }
    }

    /// Recipes without a known price add nothing: guessing a price would make the budget a guess too.
    private func cost(_ meals: [PlannedMeal]) -> Double {
        meals.reduce(0) { $0 + $1.servings * Double(byID[$1.recipeID]?.costCentsPerServing ?? 0) }
    }

    private func density(_ id: UUID) -> Double {
        guard let recipe = byID[id], recipe.kcalPerServing > 0 else { return 0 }
        return recipe.proteinPerServing / recipe.kcalPerServing
    }

    private func isWithinKcal(_ kcal: Double) -> Bool {
        abs(kcal - Double(request.kcalTarget)) <= Double(request.kcalTarget) * WeekMenuPlanner.kcalTolerance
    }

    private static func slotIndex(_ slot: MealSlot) -> Int {
        MealSlot.allCases.firstIndex(of: slot) ?? 0
    }

    /// A number in 0..<1 that depends only on the seed, the day, the meal and the recipe.
    /// `Hasher` is not usable here: its outcome differs per app launch.
    private func jitter(day: Day, slot: MealSlot, recipe: UUID) -> Double {
        var value = Self.mixed(request.seed ^ UInt64(bitPattern: Int64(day.ordinal)))
        value = Self.mixed(value ^ UInt64(Self.slotIndex(slot)))
        let bytes = withUnsafeBytes(of: recipe.uuid) { Array($0) }
        for half in [bytes.prefix(8), bytes.suffix(8)] {
            value = Self.mixed(value ^ half.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        }
        return Double(value >> 11) / 9_007_199_254_740_992
    }

    /// SplitMix64.
    private static func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
