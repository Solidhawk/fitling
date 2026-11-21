import SwiftUI
import FitlingCore

/// What a meal row in the day overview opens.
struct MealChoice: Identifiable {
    let meal: MealSlot
    var id: String { meal.rawValue }
}

struct DayView: View {
    @State private var viewModel: DayViewModel
    @State private var logging: MealChoice?
    private let food: FoodServices
    private let sync: SyncEngine
    private let partner: PartnerViewModel

    init(profile: UserProfile, sync: SyncEngine, food: FoodServices, partner: PartnerViewModel) {
        _viewModel = State(initialValue: DayViewModel(profile: profile, context: sync.context))
        self.food = food
        self.sync = sync
        self.partner = partner
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayCard(totals: viewModel.totals, targets: viewModel.targets, partner: partner)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    unknownMacrosNote
                }

                Section("water.title") {
                    HStack {
                        Text(Measurement(value: Double(viewModel.waterMl), unit: UnitVolume.milliliters), format: .measurement(width: .abbreviated, usage: .asProvided))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                        Spacer()
                        Button {
                            viewModel.addGlass()
                        } label: {
                            Label("water.add", systemImage: "drop.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("water.add")
                    }
                }
                .listRowBackground(Color.card)

                ForEach(MealSlot.allCases, id: \.self) { meal in
                    mealSection(meal)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .accessibilityIdentifier("day.list")
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.show(viewModel.day.adding(-1))
                    } label: {
                        Label("day.previous", systemImage: "chevron.left")
                    }
                    Button {
                        viewModel.show(viewModel.day.adding(1))
                    } label: {
                        Label("day.next", systemImage: "chevron.right")
                    }
                    .disabled(viewModel.isToday)
                }
            }
            .refreshable {
                await sync.sync()
                viewModel.reload()
            }
            .sheet(item: $logging, onDismiss: {
                viewModel.reload()
                // The partner's mood follows what is logged.
                partner.refresh()
            }) { choice in
                LogFoodView(
                    viewModel: LogFoodViewModel(
                        meal: choice.meal, day: viewModel.day,
                        diary: FoodDiary(context: sync.context, userID: viewModel.userID),
                        lookup: ProductLookup(context: sync.context, source: food.source),
                        search: food.search
                    ),
                    onLogged: {
                        logging = nil
                        Task { await sync.sync() }
                    }
                )
            }
        }
    }

    private var title: Text {
        if viewModel.isToday { return Text("day.today") }
        return Text(viewModel.day.startDate, format: .dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder
    private var unknownMacrosNote: some View {
        let totals = viewModel.totals
        if totals.unknownProtein + totals.unknownCarbs + totals.unknownFat > 0 {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if totals.unknownProtein > 0 { Text("day.unknown.protein \(totals.unknownProtein)") }
                if totals.unknownCarbs > 0 { Text("day.unknown.carbs \(totals.unknownCarbs)") }
                if totals.unknownFat > 0 { Text("day.unknown.fat \(totals.unknownFat)") }
            }
            .footerStyle()
        }
    }

    private func mealSection(_ meal: MealSlot) -> some View {
        Section {
            ForEach(viewModel.entriesByMeal[meal] ?? []) { entry in
                EntryRow(entry: entry)
            }
            .onDelete { offsets in
                let entries = viewModel.entriesByMeal[meal] ?? []
                for index in offsets { viewModel.delete(entries[index]) }
                Task { await sync.sync() }
            }
            Button {
                logging = MealChoice(meal: meal)
            } label: {
                Label("day.add", systemImage: "plus")
            }
            .accessibilityIdentifier("day.add.\(meal.rawValue)")
        } header: {
            HStack {
                Text(meal.titleKey)
                Spacer()
                Text(kcalText(viewModel.kcal(of: meal)))
                    .monospacedDigit()
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(Color.ink)
            .textCase(nil)
        }
        .listRowBackground(Color.card)
    }

    private func kcalText(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories).formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}

private struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.name)
                Text(amount)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer()
            Text(Measurement(value: entry.kcal.rounded(), unit: UnitEnergy.kilocalories), format: .measurement(width: .abbreviated, usage: .asProvided))
                .fontWeight(.heavy)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var amount: String {
        let quantity = entry.quantity.formatted(.number.precision(.fractionLength(0...1)))
        switch QuantityUnit(rawValue: entry.quantityUnit) {
        case .serving: return String(localized: "portion.servings \(quantity)")
        case .millilitre: return "\(quantity) \(UnitVolume.milliliters.symbol)"
        default: return "\(quantity) \(UnitMass.grams.symbol)"
        }
    }
}

/// The day as a card in the partner's colour: the partner, the kcal still to go, and the macros as
/// blocks that fill up. Without a partner the card is plain white.
struct DayCard: View {
    let totals: DayTotals
    let targets: NutritionTargets
    let partner: PartnerViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 52.0

    private var remaining: Double {
        Double(targets.kcal) - totals.kcal
    }

    var body: some View {
        // The species tint is light in both modes, so the lettering on it is the dark ribbon ink.
        let species = partner.species
        VStack(alignment: .leading, spacing: Spacing.m) {
            header(species: species)
            if let creature = partner.creature, let snapshot = partner.snapshot {
                Text(snapshot.mood.descriptionKey(name: creature.name))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MacroBlocks(eaten: totals, targets: targets)
        }
        .foregroundStyle(species == nil ? Color.ink : Color.onRibbon)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(species?.tint ?? Color.card)
                .shadow(color: Color.cardShadow, radius: 12, y: 4)
        }
        .accessibilityIdentifier("day.progress")
    }

    /// The partner beside the number; at the accessibility sizes the partner goes above it, so the
    /// number keeps the full width.
    private func header(species: Species?) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.l))
        return layout {
            if let species, let look = partner.look, let snapshot = partner.snapshot {
                PartnerFigure(species: species, look: look, energy: snapshot.energy)
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let species, let creature = partner.creature {
                    NamePlate(verbatim: creature.name, fill: species.ribbon, edge: nil)
                }
                Text(abs(remaining).rounded(), format: .number)
                    .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(remaining >= 0 ? LocalizedStringKey("day.kcal.toGo") : "day.kcal.overTarget")
                    .font(.headline.weight(.heavy))
                Text("day.kcal.eatenOf \(kcal(totals.kcal)) \(kcal(Double(targets.kcal)))")
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func kcal(_ value: Double) -> String {
        Measurement(value: value.rounded(), unit: UnitEnergy.kilocalories).formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}

extension MealSlot {
    var titleKey: LocalizedStringKey {
        switch self {
        case .breakfast: "meal.breakfast"
        case .lunch: "meal.lunch"
        case .dinner: "meal.dinner"
        case .snack: "meal.snack"
        }
    }
}

extension Day {
    /// Midnight of this day in the user's time zone, for showing it with date formatting.
    var startDate: Date {
        let parts = components
        return Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? .now
    }
}
