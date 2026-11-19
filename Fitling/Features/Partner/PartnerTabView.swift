import SwiftUI
import SwiftData
import FitlingCore

/// The partner tab: how the partner is doing, what today earns, what it wears and when it may
/// send a reminder.
struct PartnerTabView: View {
    let viewModel: PartnerViewModel
    let context: ModelContext
    @State private var editing = false
    @State private var choosing = false
    @Environment(\.openURL) private var openURL

    init(viewModel: PartnerViewModel, context: ModelContext) {
        self.viewModel = viewModel
        self.context = context
    }

    var body: some View {
        NavigationStack {
            Group {
                if let creature = viewModel.creature, let species = viewModel.species, let snapshot = viewModel.snapshot,
                   let look = viewModel.look {
                    content(creature: creature, species: species, snapshot: snapshot, look: look)
                } else {
                    ContentUnavailableView {
                        Label("partner.empty.title", systemImage: "face.smiling")
                    } description: {
                        Text("partner.empty.body")
                    } actions: {
                        Button("partner.empty.choose") { choosing = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ground)
                }
            }
            .navigationTitle("partner.title")
            .onAppear { viewModel.refresh() }
            .sheet(isPresented: $choosing) {
                PartnerSetupView(viewModel: PartnerSetupViewModel(userID: viewModel.profile.id, context: context)) { _ in
                    choosing = false
                    viewModel.refresh()
                }
            }
            .alert(
                "partner.news.title",
                isPresented: Binding(get: { !viewModel.news.isEmpty }, set: { if !$0 { viewModel.clearNews() } })
            ) {
                Button("common.ok", role: .cancel) { viewModel.clearNews() }
            } message: {
                newsText
            }
        }
    }

    private func content(creature: Creature, species: Species, snapshot: CreatureSnapshot, look: PartnerLook) -> some View {
        List {
            Section {
                hero(creature: creature, species: species, snapshot: snapshot, look: look)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                xpRow("partner.today.logging", earned: viewModel.todayXP.logging)
                xpRow("partner.today.target", earned: viewModel.todayXP.withinTarget)
                xpRow("partner.today.protein", earned: viewModel.todayXP.protein)
                xpRow("partner.today.workout", earned: viewModel.todayXP.workout)
            } header: {
                Text("partner.today.title")
            } footer: {
                Text("partner.today.footer").footerStyle()
            }
            .listRowBackground(Color.card)

            Section("partner.items.title") {
                ForEach(CreatureItem.allCases, id: \.self) { item in
                    if viewModel.isUnlocked(item) {
                        Toggle(item.titleKey, isOn: Binding(get: { viewModel.isWorn(item) }, set: { _ in viewModel.toggle(item) }))
                            .tint(Color.sprout)
                            .accessibilityIdentifier("partner.item.\(item.rawValue)")
                    } else {
                        HStack {
                            Text(item.titleKey).foregroundStyle(Color.inkSoft)
                            Spacer()
                            Label("partner.locked \(item.unlockLevel)", systemImage: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.inkSoft)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .listRowBackground(Color.card)

            Section("partner.color.title") {
                ColorSwatches(
                    species: species, count: snapshot.unlockedColorCount,
                    selection: Binding(get: { creature.colorIndex }, set: { viewModel.setColor($0) }),
                    unlockLevels: viewModel.lockedColorLevels
                )
            }
            .listRowBackground(Color.card)

            remindersSection(name: creature.name)
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .accessibilityIdentifier("partner.list")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("partner.edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            PartnerEditView(name: creature.name, tone: viewModel.tone) { name, tone in
                viewModel.rename(name)
                viewModel.setTone(tone)
            }
        }
    }

    private func hero(creature: Creature, species: Species, snapshot: CreatureSnapshot, look: PartnerLook) -> some View {
        VStack(spacing: Spacing.m) {
            PartnerFigure(species: species, look: look, energy: snapshot.energy)
                .frame(width: 200, height: 200)
                .accessibilityHidden(true)
            NamePlate(verbatim: creature.name, fill: species.ribbon)
            Text(snapshot.mood.descriptionKey(name: creature.name))
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            LevelRibbon(snapshot: snapshot)
        }
        .foregroundStyle(Color.ink)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("partner.hero")
    }

    private func xpRow(_ titleKey: LocalizedStringKey, earned: Int) -> some View {
        HStack {
            Image(systemName: earned > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(earned > 0 ? Color.ink : Color.inkSoft)
                .accessibilityHidden(true)
            Text(titleKey)
            Spacer()
            if earned > 0 {
                Text("partner.xp.earned \(earned)")
                    .fontWeight(.heavy)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func remindersSection(name: String) -> some View {
        Section {
            Toggle(
                "partner.reminders.toggle",
                isOn: Binding(get: { viewModel.reminders.isOn }, set: { isOn in Task { await viewModel.setRemindersOn(isOn) } })
            )
            .tint(Color.sprout)
            .accessibilityIdentifier("partner.reminders.toggle")
            if viewModel.reminders.isOn {
                ForEach(viewModel.reminders.times.indices, id: \.self) { index in
                    DatePicker(
                        index == 0 ? LocalizedStringKey("partner.reminders.first") : "partner.reminders.second",
                        selection: reminderTime(at: index),
                        in: ReminderTime.allowedRange,
                        displayedComponents: .hourAndMinute
                    )
                    .tint(Color.ink)
                }
            }
            if viewModel.remindersRefused {
                Button("partner.reminders.settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("partner.reminders.title")
        } footer: {
            Group {
                if viewModel.remindersRefused {
                    Text("partner.reminders.refused")
                } else {
                    Text("partner.reminders.footer \(name)")
                }
            }
            .footerStyle()
        }
        .listRowBackground(Color.card)
    }

    private func reminderTime(at index: Int) -> Binding<Date> {
        Binding(
            get: { ReminderTime.date(for: viewModel.reminders.times[index]) },
            set: { viewModel.setReminderTime(at: index, to: ReminderTime.minutes(of: $0)) }
        )
    }

    private var newsText: Text {
        let lines = viewModel.news.map(\.text)
        guard let first = lines.first else { return Text(verbatim: "") }
        return lines.dropFirst().reduce(first) { $0 + Text(verbatim: "\n") + $1 }
    }
}

/// Level and the way to the next one, as a ribbon that fills up.
private struct LevelRibbon: View {
    let snapshot: CreatureSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("partner.level \(snapshot.level)")
                    .font(.title3.weight(.heavy))
                Spacer()
                if snapshot.xpForNextLevel > 0 {
                    Text("partner.xp.progress \(snapshot.xpIntoLevel) \(snapshot.xpForNextLevel)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
            }
            GeometryReader { proxy in
                let fraction = snapshot.xpForNextLevel > 0 ? Double(snapshot.xpIntoLevel) / Double(snapshot.xpForNextLevel) : 1
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.card)
                    Capsule().fill(Color.ink)
                        .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? 12 : 0))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            if snapshot.xpForNextLevel == 0 {
                Text("partner.level.max").font(.footnote)
            }
        }
        .foregroundStyle(Color.ink)
    }
}

/// Name and voice, edited in a sheet.
private struct PartnerEditView: View {
    @State private var name: String
    @State private var tone: MessageTone
    private let onSave: (String, MessageTone) -> Void
    @Environment(\.dismiss) private var dismiss

    init(name: String, tone: MessageTone, onSave: @escaping (String, MessageTone) -> Void) {
        _name = State(initialValue: name)
        _tone = State(initialValue: tone)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("partner.setup.name", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { _, value in
                            let limited = PartnerSetupViewModel.limited(value)
                            if limited != value { name = limited }
                        }
                } header: {
                    Text("partner.setup.name")
                }
                .listRowBackground(Color.card)
                Section("partner.setup.tone") {
                    Picker("partner.setup.tone", selection: $tone) {
                        ForEach(MessageTone.allCases, id: \.self) { tone in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(tone.titleKey).foregroundStyle(Color.ink)
                                Text(tone.sampleKey).font(.footnote).foregroundStyle(Color.inkSoft)
                            }
                            .tag(tone)
                        }
                    }
                    .pickerStyle(.inline)
                    .tint(Color.ink)
                    .labelsHidden()
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("partner.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        onSave(name, tone)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// Reminder times as the pickers show them: a time today, between 08:00 and 20:59.
enum ReminderTime {
    static var allowedRange: ClosedRange<Date> {
        date(for: ReminderSettings.quietUntil)...date(for: ReminderSettings.quietFrom - 1)
    }

    static func date(for minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(of date: Date) -> Int {
        ReminderPlanner.minutes(of: date, in: .current)
    }
}

extension CreatureMood {
    /// One line on how the partner is doing and why, with its name.
    func descriptionKey(name: String) -> LocalizedStringKey {
        switch self {
        case .happy: "partner.mood.happy \(name)"
        case .content: "partner.mood.content \(name)"
        case .sluggish: "partner.mood.sluggish \(name)"
        case .tired: "partner.mood.tired \(name)"
        case .hungry: "partner.mood.hungry \(name)"
        case .asleep: "partner.mood.asleep \(name)"
        }
    }
}

extension CreatureItem {
    var titleKey: LocalizedStringKey {
        switch self {
        case .scarf: "partner.item.scarf"
        case .cap: "partner.item.cap"
        case .bow: "partner.item.bow"
        case .glasses: "partner.item.glasses"
        case .backpack: "partner.item.backpack"
        case .crown: "partner.item.crown"
        }
    }

    var displayName: String {
        switch self {
        case .scarf: String(localized: "partner.item.scarf")
        case .cap: String(localized: "partner.item.cap")
        case .bow: String(localized: "partner.item.bow")
        case .glasses: String(localized: "partner.item.glasses")
        case .backpack: String(localized: "partner.item.backpack")
        case .crown: String(localized: "partner.item.crown")
        }
    }
}

extension CreatureEvent {
    var text: Text {
        switch self {
        case let .leveledUp(level): Text("partner.news.level \(level)")
        case let .unlockedItem(item): Text("partner.news.item \(item.displayName)")
        case .unlockedColor: Text("partner.news.color")
        case let .recoveryBonus(xp): Text("partner.news.recovery \(xp)")
        }
    }
}
