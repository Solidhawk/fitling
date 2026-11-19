import SwiftUI
import FitlingCore

/// One recipe: its photo with the maker's credit, energy and macros per serving, ingredients
/// and steps.
struct RecipeDetailView: View {
    let recipe: Recipe
    let store: MenuStore
    private let languages = Locale.preferredLanguages
    private let credit: RecipeCatalog.PhotoCredit?

    init(recipe: Recipe, store: MenuStore) {
        self.recipe = recipe
        self.store = store
        credit = recipe.ownerID == nil ? RecipeCatalog.bundled()?.credit(for: recipe.id) : nil
    }

    private var steps: [String] {
        let all = recipe.steps
        for language in languages.map({ String($0.prefix(2)) }) + ["en", "nl"] {
            if let steps = all[language], !steps.isEmpty { return steps }
        }
        return all.values.first ?? []
    }

    var body: some View {
        List {
            if UIImage(named: RecipeThumbnail.photoName(recipe.id)) != nil {
                Section {
                    Image(RecipeThumbnail.photoName(recipe.id))
                        .resizable()
                        .aspectRatio(4 / 3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                } footer: {
                    if let credit {
                        Text("menu.photo.credit \(credit.author) \(credit.licence)").footerStyle()
                    }
                }
            }
            Section {
                LabeledContent("menu.recipe.kcal") {
                    Text(Measurement(value: recipe.kcalPerServing.rounded(), unit: UnitEnergy.kilocalories), format: .measurement(width: .abbreviated, usage: .food))
                        .fontWeight(.heavy)
                        .monospacedDigit()
                }
                LabeledContent("targets.protein") { grams(recipe.proteinGPerServing) }
                LabeledContent("targets.carbs") { grams(recipe.carbsGPerServing) }
                LabeledContent("targets.fat") { grams(recipe.fatGPerServing) }
            } header: {
                Text("menu.recipe.perServing")
            } footer: {
                if recipe.ownerID == nil {
                    Text("menu.recipe.source").footerStyle()
                }
            }
            .listRowBackground(Color.card)

            Section {
                ForEach(store.ingredients(of: recipe)) { ingredient in
                    HStack {
                        Text(verbatim: ingredient.name.text(preferring: languages))
                        Spacer()
                        Text(verbatim: amount(ingredient)).foregroundStyle(Color.inkSoft).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("menu.recipe.ingredients \(recipe.servings)")
            }
            .listRowBackground(Color.card)

            if !steps.isEmpty {
                Section("menu.recipe.steps") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { item in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                            Text(verbatim: "\(item.offset + 1)").font(.headline.weight(.heavy)).monospacedDigit()
                            Text(verbatim: item.element)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Color.card)
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle(Text(verbatim: recipe.title.text(preferring: languages)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func grams(_ value: Double) -> some View {
        Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g").monospacedDigit()
    }

    private func amount(_ ingredient: RecipeIngredient) -> String {
        let quantity = ingredient.quantity.formatted(.number.precision(.fractionLength(0...2)))
        switch ingredient.unit {
        case "g": return "\(quantity) \(UnitMass.grams.symbol)"
        case "ml": return "\(quantity) \(UnitVolume.milliliters.symbol)"
        case "tbsp": return String(localized: "menu.unit.tbsp \(quantity)")
        case "tsp": return String(localized: "menu.unit.tsp \(quantity)")
        default: return String(localized: "menu.unit.piece \(quantity)")
        }
    }
}

/// All recipes, with the user's own ones to add or delete.
struct RecipeListView: View {
    let viewModel: MenuViewModel
    let onOpen: (Recipe) -> Void
    @State private var creating = false
    @State private var query = ""
    private let languages = Locale.preferredLanguages

    init(viewModel: MenuViewModel, onOpen: @escaping (Recipe) -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
    }

    private var shown: [Recipe] {
        let term = FoodDiary.searchKey(query)
        return viewModel.recipes.filter { term.isEmpty || FoodDiary.searchKey($0.title.text(preferring: languages)).contains(term) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    creating = true
                } label: {
                    Label("menu.recipe.new", systemImage: "plus")
                }
            }
            .listRowBackground(Color.card)
            Section {
                ForEach(shown) { recipe in
                    Button {
                        onOpen(recipe)
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                    .swipeActions {
                        if recipe.ownerID != nil {
                            Button("menu.recipe.delete", role: .destructive) { viewModel.delete(recipe) }
                        }
                    }
                }
            }
            .listRowBackground(Color.card)
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .searchable(text: $query, prompt: Text("menu.recipes.search"))
        .navigationTitle("menu.recipes")
        .sheet(isPresented: $creating) {
            OwnRecipeForm { own in viewModel.create(own) != nil }
        }
    }
}

/// A recipe of the user's own: title, servings, time, meals, energy and macros per serving,
/// and the ingredients for the shopping list.
struct OwnRecipeForm: View {
    @State private var recipe = MenuStore.OwnRecipe()
    @State private var ingredientName = ""
    @State private var ingredientQuantity: Double?
    @State private var ingredientUnit = "g"
    private let onSave: (MenuStore.OwnRecipe) -> Bool
    @Environment(\.dismiss) private var dismiss

    init(onSave: @escaping (MenuStore.OwnRecipe) -> Bool) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("menu.own.title", text: $recipe.title)
                        .accessibilityIdentifier("menu.own.title")
                    Stepper(value: $recipe.servings, in: 1...20) { Text("menu.own.servings \(recipe.servings)") }
                    Stepper(value: $recipe.cookMinutes, in: 0...600, step: 5) { Text("menu.own.minutes \(recipe.cookMinutes)") }
                }
                .listRowBackground(Color.card)
                Section("menu.own.meals") {
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        Toggle(slot.titleKey, isOn: Binding(
                            get: { recipe.slots.contains(slot) },
                            set: { isOn in if isOn { recipe.slots.insert(slot) } else { recipe.slots.remove(slot) } }
                        ))
                        .tint(Color.sprout)
                    }
                }
                .listRowBackground(Color.card)
                Section {
                    numberField("menu.own.kcal", value: $recipe.kcal, unit: UnitEnergy.kilocalories.symbol)
                    numberField("targets.protein", value: $recipe.protein, unit: UnitMass.grams.symbol)
                    numberField("targets.carbs", value: $recipe.carbs, unit: UnitMass.grams.symbol)
                    numberField("targets.fat", value: $recipe.fat, unit: UnitMass.grams.symbol)
                } header: {
                    Text("menu.recipe.perServing")
                } footer: {
                    Text("menu.own.values.footer").footerStyle()
                }
                .listRowBackground(Color.card)
                Section("menu.recipe.ingredients.title") {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { item in
                        Text(verbatim: "\(item.element.quantity.formatted()) \(item.element.unit) \(item.element.name)")
                    }
                    .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                    HStack {
                        TextField("menu.own.ingredient", text: $ingredientName)
                        TextField("menu.own.quantity", value: $ingredientQuantity, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 72)
                        Picker("menu.own.unit", selection: $ingredientUnit) {
                            ForEach(["g", "ml", "piece", "tbsp", "tsp"], id: \.self) { unit in
                                Text(unitKey(unit)).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .tint(Color.ink)
                    }
                    Button("menu.own.addIngredient") {
                        guard let quantity = ingredientQuantity, quantity > 0, !ingredientName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        recipe.ingredients.append((ingredientName.trimmingCharacters(in: .whitespaces), quantity, ingredientUnit))
                        ingredientName = ""
                        ingredientQuantity = nil
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("menu.recipe.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        if onSave(recipe) { dismiss() }
                    }
                    .disabled(!recipe.isComplete)
                }
            }
        }
    }

    private func numberField(_ label: LocalizedStringKey, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 100)
            Text(verbatim: unit).foregroundStyle(Color.inkSoft)
        }
    }

    private func unitKey(_ unit: String) -> LocalizedStringKey {
        switch unit {
        case "g": "menu.unitName.g"
        case "ml": "menu.unitName.ml"
        case "tbsp": "menu.unitName.tbsp"
        case "tsp": "menu.unitName.tsp"
        default: "menu.unitName.piece"
        }
    }
}

/// Which meals the menu plans, what to leave out, how long cooking may take and meal prep.
struct MenuPreferencesView: View {
    let store: MenuStore
    @State private var preferences: MenuPreferences?
    @Environment(\.dismiss) private var dismiss

    static let tags = ["meat", "fish", "dairy", "egg", "gluten", "nuts", "soy", "sesame"]
    static let cookLimits: [Int?] = [nil, 15, 30, 45, 60]

    init(store: MenuStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            List {
                if let preferences {
                    Section("menu.prefs.meals") {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Toggle(slot.titleKey, isOn: Binding(
                                get: { preferences.mealSlots.contains(slot.rawValue) },
                                set: { isOn in
                                    var slots = Set(preferences.mealSlots)
                                    if isOn { slots.insert(slot.rawValue) } else if slots.count > 1 { slots.remove(slot.rawValue) }
                                    preferences.mealSlots = MealSlot.allCases.map(\.rawValue).filter(slots.contains)
                                    store.save(preferences)
                                }
                            ))
                            .tint(Color.sprout)
                        }
                    }
                    .listRowBackground(Color.card)
                    Section {
                        ForEach(Self.tags, id: \.self) { tag in
                            Toggle(tagKey(tag), isOn: Binding(
                                get: { preferences.excludedTags.contains(tag) },
                                set: { isOn in
                                    preferences.excludedTags = Self.tags.filter { $0 == tag ? isOn : preferences.excludedTags.contains($0) }
                                    store.save(preferences)
                                }
                            ))
                            .tint(Color.sprout)
                        }
                    } header: {
                        Text("menu.prefs.without")
                    }
                    .listRowBackground(Color.card)
                    Section {
                        Picker("menu.prefs.cookTime", selection: Binding(
                            get: { preferences.maxCookMinutes },
                            set: { preferences.maxCookMinutes = $0; store.save(preferences) }
                        )) {
                            ForEach(Self.cookLimits, id: \.self) { limit in
                                if let limit {
                                    Text("menu.prefs.minutes \(limit)").tag(Int?.some(limit))
                                } else {
                                    Text("menu.prefs.noLimit").tag(Int?.none)
                                }
                            }
                        }
                        .tint(Color.ink)
                        Toggle("menu.prefs.mealPrep", isOn: Binding(
                            get: { preferences.mealPrep },
                            set: { preferences.mealPrep = $0; store.save(preferences) }
                        ))
                        .tint(Color.sprout)
                    } footer: {
                        Text("menu.prefs.mealPrep.footer").footerStyle()
                    }
                    .listRowBackground(Color.card)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("menu.preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.ok") { dismiss() }
                }
            }
            .onAppear { preferences = store.preferences() }
        }
    }

    private func tagKey(_ tag: String) -> LocalizedStringKey {
        switch tag {
        case "meat": "menu.tag.meat"
        case "fish": "menu.tag.fish"
        case "dairy": "menu.tag.dairy"
        case "egg": "menu.tag.egg"
        case "gluten": "menu.tag.gluten"
        case "nuts": "menu.tag.nuts"
        case "soy": "menu.tag.soy"
        default: "menu.tag.sesame"
        }
    }
}
