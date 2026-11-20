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

    init(profile: UserProfile, sync: SyncEngine, food: FoodServices) {
        _viewModel = State(initialValue: DayViewModel(profile: profile, context: sync.context))
        self.food = food
        self.sync = sync
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayProgressCard(totals: viewModel.totals, targets: viewModel.targets)
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
            .sheet(item: $logging, onDismiss: { viewModel.reload() }) { choice in
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

/// The day's progress: kcal eaten against the target, and a ribbon per macro that fills up.
struct DayProgressCard: View {
    let totals: DayTotals
    let targets: NutritionTargets

    private var remaining: Double {
        Double(targets.kcal) - totals.kcal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.l) {
                KcalRing(fraction: totals.kcal / Double(max(targets.kcal, 1)))
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    NamePlate("day.eaten", fill: Color.track, foreground: Color.ink, edge: nil)
                    Text(kcal(totals.kcal))
                        .font(.largeTitle.weight(.heavy))
                        .monospacedDigit()
                    Group {
                        if remaining >= 0 {
                            Text("day.kcal.remaining \(kcal(remaining))")
                        } else {
                            Text("day.kcal.over \(kcal(-remaining))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
                }
            }
            .accessibilityElement(children: .combine)
            MacroRibbon(titleKey: "targets.protein", grams: totals.proteinG, target: targets.proteinG, fill: Color.protein)
            MacroRibbon(titleKey: "targets.carbs", grams: totals.carbsG, target: targets.carbsG, fill: Color.carbs)
            MacroRibbon(titleKey: "targets.fat", grams: totals.fatG, target: targets.fatG, fill: Color.fat)
        }
        .foregroundStyle(Color.ink)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.card)
                .shadow(color: Color.cardShadow, radius: 12, y: 4)
        }
        .accessibilityIdentifier("day.progress")
    }

    private func kcal(_ value: Double) -> String {
        Measurement(value: value.rounded(), unit: UnitEnergy.kilocalories).formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}

/// Eaten against the target as one ring in ink on the track colour. Past the target the ring
/// stays full; the text says how much over.
private struct KcalRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.track, lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A macro ribbon that fills from the left as the day is logged; ink text on the ribbon colour.
private struct MacroRibbon: View {
    let titleKey: LocalizedStringKey
    let grams: Double
    let target: Int
    let fill: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let fraction = min(max(grams / Double(max(target, 1)), 0), 1)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        layout {
            Text(titleKey)
                .font(.subheadline.weight(.bold))
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Spacing.s)
            }
            Text("day.macro.progress \(grams.rounded().formatted()) \(target.formatted())")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
        }
        .foregroundStyle(Color.onRibbon)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, minHeight: Radius.ribbon * 2, alignment: .leading)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // The empty part is a pale tint of the ribbon colour on white, in dark mode too:
                    // the ink text needs a light ground (accessibility audit, TASKS 7.2).
                    RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous)
                        .fill(Color.white)
                    RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous)
                        .fill(fill.opacity(0.35))
                    RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous)
                        .fill(fill)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? Radius.ribbon * 2 : 0))
                }
            }
        }
        .accessibilityElement(children: .combine)
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
