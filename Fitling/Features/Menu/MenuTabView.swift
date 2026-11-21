import SwiftUI
import SwiftData
import FitlingCore

enum MenuRoute: Hashable {
    case recipe(UUID)
    case recipes
    case shopping
}

/// The week menu: per day the planned meals, to pin, swap or log with one tap.
struct MenuTabView: View {
    @State private var viewModel: MenuViewModel
    @State private var path: [MenuRoute] = []
    @State private var swapping: MealPlanEntry?
    @State private var editingPreferences = false
    @State private var generating = false
    private let sync: SyncEngine
    private let profile: UserProfile
    private let shopping: ShoppingServices
    private let languages = Locale.preferredLanguages

    init(profile: UserProfile, sync: SyncEngine, shopping: ShoppingServices) {
        _viewModel = State(initialValue: MenuViewModel(profile: profile, context: sync.context))
        self.sync = sync
        self.profile = profile
        self.shopping = shopping
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if viewModel.entries.isEmpty {
                    Section {
                        Text("menu.empty").footerStyle()
                        Button("menu.generate") { generating = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .buttonRow()
                            .accessibilityIdentifier("menu.generate.first")
                    }
                    .listRowBackground(Color.clear)
                }
                if !viewModel.issues.isEmpty {
                    Section("menu.issues.title") {
                        ForEach(Array(viewModel.issues.enumerated()), id: \.offset) { item in
                            Label { Text(item.element.text) } icon: { Image(systemName: "exclamationmark.triangle") }
                        }
                    }
                    .listRowBackground(Color.card)
                }
                ForEach(viewModel.days, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            entryRow(entry)
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.day.startDate, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.headline.weight(.heavy))
                            Spacer(minLength: Spacing.s)
                            // Other meals for this day only; pinned and logged meals stay.
                            Button {
                                viewModel.renew(group.day)
                            } label: {
                                Label("menu.day.renew", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote.weight(.bold))
                            }
                            .accessibilityIdentifier("menu.day.renew.\(group.day.isoString)")
                        }
                        .foregroundStyle(Color.ink)
                        .textCase(nil)
                    }
                    .listRowBackground(Color.card)
                }
                Section {
                    NavigationLink(value: MenuRoute.shopping) {
                        Label("shopping.title", systemImage: "cart")
                    }
                    .accessibilityIdentifier("menu.shopping")
                    NavigationLink(value: MenuRoute.recipes) {
                        Label("menu.recipes", systemImage: "book")
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .accessibilityIdentifier("menu.list")
            .navigationTitle("menu.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editingPreferences = true
                    } label: {
                        Label("menu.preferences", systemImage: "slider.horizontal.3")
                    }
                }
                if !viewModel.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("menu.regenerate") { generating = true }
                            .accessibilityIdentifier("menu.generate")
                    }
                }
            }
            .navigationDestination(for: MenuRoute.self) { route in
                switch route {
                case let .recipe(id):
                    if let recipe = viewModel.store.recipe(id) {
                        RecipeDetailView(recipe: recipe, store: viewModel.store)
                    }
                case .recipes:
                    RecipeListView(viewModel: viewModel) { path.append(.recipe($0.id)) }
                case .shopping:
                    ShoppingListView(viewModel: ShoppingViewModel(
                        profile: profile, sync: sync, services: shopping,
                        listName: String(localized: "shopping.title"), ownerName: String(localized: "shopping.member.default")
                    ))
                }
            }
            .onAppear { viewModel.reload() }
            .sheet(item: $swapping) { entry in
                RecipePicker(recipes: viewModel.recipes(for: entry)) { recipe in
                    viewModel.swap(entry, to: recipe)
                }
            }
            .sheet(isPresented: $generating, onDismiss: { Task { await sync.sync() } }) {
                MenuGeneratorView(viewModel: viewModel)
            }
            .sheet(isPresented: $editingPreferences, onDismiss: { Task { await sync.sync() } }) {
                MenuPreferencesView(store: viewModel.store)
            }
        }
    }

    private func entryRow(_ entry: MealPlanEntry) -> some View {
        let recipe = viewModel.recipe(of: entry)
        return Button {
            path.append(.recipe(entry.recipeID))
        } label: {
            HStack(spacing: Spacing.m) {
                RecipeThumbnail(recipeID: entry.recipeID, title: recipe?.title.text(preferring: languages) ?? "")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text((MealSlot(rawValue: entry.meal) ?? .dinner).titleKey)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.inkSoft)
                    Text(verbatim: recipe?.title.text(preferring: languages) ?? "")
                        .foregroundStyle(Color.ink)
                    Text("menu.entry.detail \(entry.servings.formatted(.number.precision(.fractionLength(0...2)))) \(Int(((recipe?.kcalPerServing ?? 0) * entry.servings).rounded()))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer(minLength: 0)
                if entry.loggedEntryID != nil {
                    Image(systemName: "checkmark.circle.fill").accessibilityLabel(Text("menu.logged"))
                } else if entry.isPinned {
                    Image(systemName: "pin.fill").accessibilityLabel(Text("menu.pinned"))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading) {
            if entry.loggedEntryID == nil {
                Button {
                    viewModel.log(entry)
                    Task { await sync.sync() }
                } label: {
                    Label("menu.log", systemImage: "checkmark")
                }
                .tint(Color.sprout)
            }
        }
        .swipeActions(edge: .trailing) {
            if entry.loggedEntryID == nil {
                Button {
                    swapping = entry
                } label: {
                    Label("menu.swap", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Color.ink)
                Button {
                    viewModel.togglePin(entry)
                } label: {
                    Label(entry.isPinned ? LocalizedStringKey("menu.unpin") : "menu.pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
                }
                .tint(Color.pebble)
            }
        }
        .contextMenu {
            if entry.loggedEntryID == nil {
                Button("menu.log", systemImage: "checkmark") {
                    viewModel.log(entry)
                    Task { await sync.sync() }
                }
                Button("menu.swap", systemImage: "arrow.triangle.2.circlepath") { swapping = entry }
                Button(entry.isPinned ? LocalizedStringKey("menu.unpin") : "menu.pin", systemImage: "pin") { viewModel.togglePin(entry) }
                Button("menu.remove", systemImage: "trash", role: .destructive) { viewModel.remove(entry) }
            }
        }
        .accessibilityIdentifier("menu.entry.\(entry.plannedOn).\(entry.meal)")
    }
}

/// The recipe's own photo, or its first letter on a track tile when it has none (own recipes).
struct RecipeThumbnail: View {
    let recipeID: UUID
    let title: String
    var size: CGFloat = 56

    static func photoName(_ id: UUID) -> String {
        "Recipes/\(id.uuidString.lowercased())"
    }

    var body: some View {
        Group {
            if UIImage(named: Self.photoName(recipeID)) != nil {
                Image(Self.photoName(recipeID)).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.track
                    Text(verbatim: ProductThumbnail.initial(of: title))
                        .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Picks a recipe for one meal.
struct RecipePicker: View {
    let recipes: [Recipe]
    let onPick: (Recipe) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private let languages = Locale.preferredLanguages

    init(recipes: [Recipe], onPick: @escaping (Recipe) -> Void) {
        self.recipes = recipes
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(recipes.filter { query.isEmpty || FoodDiary.searchKey($0.title.text(preferring: languages)).contains(FoodDiary.searchKey(query)) }) { recipe in
                    Button {
                        onPick(recipe)
                        dismiss()
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .searchable(text: $query, prompt: Text("menu.recipes.search"))
            .navigationTitle("menu.swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: Spacing.m) {
            RecipeThumbnail(recipeID: recipe.id, title: recipe.title.text(preferring: Locale.preferredLanguages))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: recipe.title.text(preferring: Locale.preferredLanguages)).foregroundStyle(Color.ink)
                Text("menu.recipe.detail \(Int(recipe.kcalPerServing.rounded())) \(recipe.cookMinutes)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension MenuIssue {
    var text: LocalizedStringKey {
        switch self {
        case let .noRecipes(slot): "menu.issue.noRecipes \(slot.displayName)"
        case let .kcalOutOfRange(day, kcal):
            "menu.issue.kcal \(day.startDate.formatted(.dateTime.weekday(.wide))) \(kcal)"
        case let .proteinShort(day, missing):
            "menu.issue.protein \(day.startDate.formatted(.dateTime.weekday(.wide))) \(missing)"
        case let .overBudget(cents):
            "menu.issue.budget \((Double(cents) / 100).formatted(.currency(code: "EUR")))"
        }
    }
}

extension MealSlot {
    var displayName: String {
        switch self {
        case .breakfast: String(localized: "meal.breakfast")
        case .lunch: String(localized: "meal.lunch")
        case .dinner: String(localized: "meal.dinner")
        case .snack: String(localized: "meal.snack")
        }
    }
}
