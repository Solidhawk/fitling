import Foundation
import Observation
import SwiftData
import FitlingCore

/// The partner tab: the partner as the logs make it, its level, what it has unlocked, what it
/// wears and when it may send a reminder.
@Observable
@MainActor
final class PartnerViewModel {
    private(set) var creature: Creature?
    private(set) var snapshot: CreatureSnapshot?
    /// XP earned so far today; it is added once the day is over.
    private(set) var todayXP = XPBreakdown()
    /// What happened since the partner screen last showed it: a level, an accessory, a colour.
    private(set) var news: [CreatureEvent] = []
    private(set) var reminders: ReminderSettings
    /// Set when the user turned reminders on and the system said no.
    private(set) var remindersRefused = false

    let profile: UserProfile
    private let history: CreatureHistory
    private let delivery: any ReminderDelivery
    private let store: ReminderSettingsStore

    init(
        profile: UserProfile, context: ModelContext, delivery: any ReminderDelivery, defaults: UserDefaults = .standard,
        timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init
    ) {
        self.profile = profile
        history = CreatureHistory(context: context, profile: profile, timeZone: timeZone, now: now)
        self.delivery = delivery
        let store = ReminderSettingsStore(defaults: defaults)
        self.store = store
        reminders = store.load()
    }

    var look: PartnerLook? {
        guard let snapshot, let creature else { return nil }
        return PartnerLook(snapshot: snapshot, items: wornItems(of: creature))
    }

    var species: Species? {
        creature.flatMap { Species(rawValue: $0.species) }
    }

    var tone: MessageTone {
        creature.flatMap { MessageTone(rawValue: $0.tone) } ?? .sweet
    }

    /// Folds finished days into the partner, works out how it is now and plans its reminders.
    /// Called at start, when the app comes back, after a sync and when the day changes.
    func refresh() {
        creature = history.context.creature(of: profile.id)
        guard let creature else {
            snapshot = nil
            return
        }
        news += history.update(creature)
        snapshot = history.snapshot(of: creature)
        todayXP = history.todayRecord().map(CreatureEngine.xp(for:)) ?? XPBreakdown()
        planReminders()
    }

    func clearNews() {
        news = []
    }

    // MARK: Accessories and colours

    func isUnlocked(_ item: CreatureItem) -> Bool {
        snapshot?.unlockedItems.contains(item) ?? false
    }

    func isWorn(_ item: CreatureItem) -> Bool {
        creature?.equippedItems.contains(item.rawValue) ?? false
    }

    /// Puts an unlocked item on or takes it off. A cap and a crown do not fit on one head: putting
    /// one on takes the other off.
    func toggle(_ item: CreatureItem) {
        guard let creature, isUnlocked(item), let unlocked = snapshot?.unlockedItems else { return }
        // The same rule as on the web (FitlingCore), in the fixed order both store.
        let worn = CreatureEngine.wearing(wornItems(of: creature), toggling: item, unlocked: unlocked)
        save(creature) { $0.equippedItems = worn.map(\.rawValue) }
    }

    func setColor(_ index: Int) {
        guard let creature, let snapshot, index >= 0, index < snapshot.unlockedColorCount, index != creature.colorIndex else { return }
        save(creature) { $0.colorIndex = index }
        refresh()
    }

    /// Levels at which the colours that are still locked unlock.
    var lockedColorLevels: [Int] {
        guard let snapshot else { return [] }
        return CreatureEngine.colorUnlockLevels.filter { $0 > snapshot.level }
    }

    // MARK: Name and voice

    func rename(_ name: String) {
        let cleaned = PartnerSetupViewModel.limited(name.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let creature, !cleaned.isEmpty, cleaned != creature.name else { return }
        save(creature) { $0.name = cleaned }
        planReminders()
    }

    func setTone(_ tone: MessageTone) {
        guard let creature, tone.rawValue != creature.tone else { return }
        save(creature) { $0.tone = tone.rawValue }
        planReminders()
    }

    // MARK: Reminders

    /// Turning reminders on asks the system first; when it refuses, they stay off.
    func setRemindersOn(_ isOn: Bool) async {
        remindersRefused = false
        if isOn, !(await delivery.requestPermission()) {
            remindersRefused = true
            return
        }
        reminders.isOn = isOn
        store.save(reminders)
        planReminders()
    }

    /// `minutes` after midnight; only times outside the quiet hours are kept.
    func setReminderTime(at index: Int, to minutes: Int) {
        guard reminders.times.indices.contains(index), ReminderSettings.isAllowed(minutes) else { return }
        reminders.times[index] = minutes
        store.save(reminders)
        planReminders()
    }

    private func planReminders() {
        guard let creature else { return }
        let planned = ReminderPlanner.plan(reminders, tone: tone, now: history.now(), timeZone: history.timeZone) { day in
            history.snapshot(of: creature, on: day).map(CreatureEngine.topic(for:)) ?? .hungry
        }
        delivery.replace(with: planned, title: creature.name)
    }

    private func wornItems(of creature: Creature) -> [CreatureItem] {
        creature.equippedItems.compactMap(CreatureItem.init(rawValue:))
    }

    private func save(_ creature: Creature, change: (Creature) -> Void) {
        change(creature)
        creature.updatedAt = history.now()
        creature.needsPush = true
        try? history.context.save()
    }
}
