import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
struct PartnerFixture {
    let container: ModelContainer
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let delivery = FakeReminderDelivery()
    let defaults: UserDefaults
    var context: ModelContext { container.mainContext }
    var today: Day { Day(now, timeZone: .gmt) }

    init() throws {
        container = try makeModelContainer(inMemory: true)
        let suite = "PartnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
    }

    @discardableResult
    func profile(kcal: Int = 2000, protein: Int = 120) -> UserProfile {
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        let profile = UserProfile(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body,
            targets: NutritionTargets(kcal: kcal, proteinG: protein, carbsG: 250, fatG: 70), targetsAreManual: false, updatedAt: now
        )
        context.insert(profile)
        try? context.save()
        return profile
    }

    @discardableResult
    func creature(createdDaysAgo: Int = 3, xp: Int = 0, species: Species = .pip) -> Creature {
        let state = CreatureState(species: species, colorIndex: 0, tone: .sweet, createdOn: today.adding(-createdDaysAgo), xp: xp)
        let creature = Creature(userID: userID, name: "Pip", state: state, updatedAt: now.addingTimeInterval(-86_400))
        creature.needsPush = false
        context.insert(creature)
        try? context.save()
        return creature
    }

    func log(kcal: Double, protein: Double? = 30, on day: Day, meal: MealSlot = .lunch) {
        let entry = FoodEntry(id: UUID(), userID: userID, consumedOn: day, meal: meal, name: "Maaltijd", quantity: 100, quantityUnit: "g", kcal: kcal, updatedAt: now)
        entry.proteinG = protein
        context.insert(entry)
        try? context.save()
    }

    func history(_ profile: UserProfile) -> CreatureHistory {
        CreatureHistory(context: context, profile: profile, timeZone: .gmt, now: { [now] in now })
    }

    func setup() -> PartnerSetupViewModel {
        PartnerSetupViewModel(userID: userID, context: context, timeZone: .gmt, now: { [now] in now })
    }

    func partner(_ profile: UserProfile) -> PartnerViewModel {
        PartnerViewModel(profile: profile, context: context, delivery: delivery, defaults: defaults, timeZone: .gmt, now: { [now] in now })
    }
}

// MARK: - 3.1 Partner kiezen

@MainActor
@Suite struct PartnerSetupTests {
    let fixture: PartnerFixture
    init() throws { fixture = try PartnerFixture() }

    @Test func setupStoresTheChoices() throws {
        let setup = fixture.setup()
        #expect(!setup.canSave)
        setup.choose(.ember, defaultName: "Ember")
        setup.name = "Vonk"
        setup.colorIndex = 2
        setup.tone = .funny
        try #require(setup.save() != nil)

        let stored = try #require(fixture.context.creature(of: fixture.userID))
        #expect(stored.species == "ember")
        #expect(stored.name == "Vonk")
        #expect(stored.colorIndex == 2)
        #expect(stored.tone == "funny")
        #expect(stored.createdOn == fixture.today.isoString)
        #expect(stored.bodyShape == CreatureEngine.startShape)
        #expect(stored.xp == 0)
        #expect(stored.needsPush)
    }

    @Test func nameIsTrimmedAndLimited() throws {
        let setup = fixture.setup()
        setup.choose(.pip, defaultName: "Pip")
        setup.name = "   Pip de Grote Ontdekkingsreiziger   "
        #expect(setup.cleanedName == "Pip de Grote Ontdekkings")

        // Postgres counts code points: a family emoji is seven of them, so three fit in 24.
        let family = "👨‍👩‍👧‍👦"
        setup.name = String(repeating: family, count: 4)
        #expect(setup.cleanedName == String(repeating: family, count: 3))
        #expect(setup.cleanedName.unicodeScalars.count <= PartnerSetupViewModel.nameLimit)

        setup.name = "      "
        #expect(!setup.canSave)
        setup.name = "  Pippa "
        let saved = try #require(setup.save())
        #expect(saved.name == "Pippa")
    }

    @Test func choosingAnotherSpeciesOnlyReplacesTheSuggestedName() {
        let setup = fixture.setup()
        setup.choose(.sprout, defaultName: "Sprout")
        #expect(setup.name == "Sprout")
        setup.choose(.pebble, defaultName: "Pebble")
        #expect(setup.name == "Pebble")
        setup.name = "Keitje"
        setup.choose(.pip, defaultName: "Pip")
        #expect(setup.name == "Keitje")
    }

    @Test func aPartnerFromAnotherDeviceIsKept() throws {
        let existing = fixture.creature()
        let setup = fixture.setup()
        setup.choose(.sprout, defaultName: "Sprout")
        let saved = try #require(setup.save())
        #expect(saved === existing)
        #expect(try fixture.context.fetch(FetchDescriptor<Creature>()).count == 1)
    }
}

// MARK: - 3.2 Dagen samenstellen en verwerken

@MainActor
@Suite struct CreatureHistoryTests {
    let fixture: PartnerFixture
    init() throws { fixture = try PartnerFixture() }

    @Test func buildsOneRecordPerDayWithLogs() throws {
        let profile = fixture.profile()
        let yesterday = fixture.today.adding(-1)
        fixture.log(kcal: 600, protein: 40, on: yesterday, meal: .breakfast)
        fixture.log(kcal: 900, protein: nil, on: yesterday, meal: .dinner)
        fixture.log(kcal: 500, protein: 25, on: fixture.today)

        let records = fixture.history(profile).records(from: fixture.today.adding(-6), through: fixture.today)

        try #require(records.map(\.day) == [yesterday, fixture.today])
        #expect(records[0].kcal == 1500)
        #expect(records[0].proteinG == 40)
        #expect(records[0].entryCount == 2)
        #expect(records[1].entryCount == 1)
        #expect(!records[0].workoutCompleted)
    }

    @Test func deletedEntriesDoNotCount() {
        let profile = fixture.profile()
        fixture.log(kcal: 600, on: fixture.today)
        let entry = try? fixture.context.fetch(FetchDescriptor<FoodEntry>()).first
        entry?.deletedAt = fixture.now
        try? fixture.context.save()
        #expect(fixture.history(profile).records(from: fixture.today, through: fixture.today).isEmpty)
    }

    @Test func usesTheTargetOfThatDay() {
        let profile = fixture.profile(kcal: 2000)
        let earlier = fixture.today.adding(-5)
        let change = fixture.today.adding(-2)
        fixture.context.recordTargets(NutritionTargets(kcal: 2000, proteinG: 120, carbsG: 250, fatG: 70), for: fixture.userID, from: earlier, at: fixture.now)
        fixture.context.recordTargets(NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 80), for: fixture.userID, from: change, at: fixture.now)
        fixture.log(kcal: 1800, on: change.adding(-1))
        fixture.log(kcal: 2400, on: change)

        let records = fixture.history(profile).records(from: earlier, through: fixture.today)

        #expect(records.map(\.kcalTarget) == [2000, 2500])
        #expect(records.map(\.proteinTargetG) == [120, 150])
    }

    @Test func aFinishedWorkoutCounts() throws {
        let profile = fixture.profile()
        let yesterday = fixture.today.adding(-1)
        let finished = WorkoutSession(id: UUID(), userID: fixture.userID, programDayID: nil, performedOn: yesterday, startedAt: fixture.now, updatedAt: fixture.now)
        finished.endedAt = fixture.now
        let unfinished = WorkoutSession(id: UUID(), userID: fixture.userID, programDayID: nil, performedOn: fixture.today, startedAt: fixture.now, updatedAt: fixture.now)
        fixture.context.insert(finished)
        fixture.context.insert(unfinished)
        try? fixture.context.save()

        let records = fixture.history(profile).records(from: yesterday, through: fixture.today)

        try #require(records.map(\.day) == [yesterday])
        #expect(records[0].workoutCompleted)
        #expect(records[0].entryCount == 0)
    }

    @Test func workoutFromHealthKitCounts() {
        let profile = fixture.profile()
        fixture.log(kcal: 2000, on: fixture.today)
        fixture.context.insert(DayActivity(day: fixture.today, workoutKcal: 320, updatedAt: fixture.now))
        try? fixture.context.save()

        let records = fixture.history(profile).records(from: fixture.today, through: fixture.today)

        #expect(records.first?.workoutCompleted == true)
    }

    @Test func advanceIsAppliedAndSavedOnce() throws {
        let profile = fixture.profile(kcal: 2000, protein: 120)
        let creature = fixture.creature(createdDaysAgo: 3)
        for offset in 1...3 {
            fixture.log(kcal: 2000, protein: 130, on: fixture.today.adding(-offset))
        }
        let history = fixture.history(profile)

        history.update(creature)

        #expect(creature.lastProcessedOn == fixture.today.adding(-1).isoString)
        // Each of the three days: logged (10), within the target (40) and protein reached (20).
        #expect(creature.xp == 210)
        #expect(creature.needsPush)
        #expect(creature.updatedAt == fixture.now)

        creature.needsPush = false
        try fixture.context.save()
        let events = history.update(creature)

        #expect(events.isEmpty)
        #expect(!creature.needsPush)
        #expect(creature.xp == 210)
    }
}

// MARK: - 3.4 Level, XP en vrijspelen

@MainActor
@Suite struct PartnerViewModelTests {
    let fixture: PartnerFixture
    init() throws { fixture = try PartnerFixture() }

    @Test func lockedItemsCannotBeWorn() {
        let partner = fixture.partner(fixture.profile())
        // Made today: there is no finished day to fold in, so nothing else changes the partner.
        let creature = fixture.creature(createdDaysAgo: 0, xp: 0)
        partner.refresh()

        #expect(!partner.isUnlocked(.scarf))
        partner.toggle(.scarf)
        #expect(creature.equippedItems.isEmpty)
        #expect(!creature.needsPush)
    }

    @Test func wearingACapTakesOffTheCrown() {
        let partner = fixture.partner(fixture.profile())
        let creature = fixture.creature(xp: CreatureEngine.xpRequired(forLevel: 15))
        partner.refresh()

        partner.toggle(.crown)
        partner.toggle(.scarf)
        #expect(creature.equippedItems == ["scarf", "crown"])
        partner.toggle(.cap)
        #expect(creature.equippedItems == ["scarf", "cap"])
        #expect(creature.needsPush)
        partner.toggle(.scarf)
        #expect(creature.equippedItems == ["cap"])
    }

    @Test func lockedColoursCannotBeChosen() {
        let partner = fixture.partner(fixture.profile())
        let creature = fixture.creature(xp: 0)
        partner.refresh()

        partner.setColor(3)
        #expect(creature.colorIndex == 0)
        #expect(partner.lockedColorLevels == CreatureEngine.colorUnlockLevels)
        partner.setColor(2)
        #expect(creature.colorIndex == 2)
    }

    @Test func finishedDaysAreReportedOnce() {
        let partner = fixture.partner(fixture.profile(kcal: 2000, protein: 120))
        fixture.creature(createdDaysAgo: 1, xp: CreatureEngine.xpRequired(forLevel: 2) - 20)
        fixture.log(kcal: 2000, protein: 130, on: fixture.today.adding(-1))

        partner.refresh()
        #expect(partner.news.contains(.leveledUp(to: 2)))
        #expect(partner.news.contains(.unlockedItem(.scarf)))
        #expect(partner.snapshot?.level == 2)

        partner.clearNews()
        partner.refresh()
        #expect(partner.news.isEmpty)
    }

    @Test func todayShowsWhatIsEarnedSoFar() {
        let partner = fixture.partner(fixture.profile(kcal: 2000, protein: 120))
        fixture.creature()
        fixture.log(kcal: 800, protein: 20, on: fixture.today)

        partner.refresh()

        #expect(partner.todayXP.logging > 0)
        #expect(partner.todayXP.withinTarget == 0)
        #expect(partner.todayXP.protein == 0)
    }
}

// MARK: - 3.5 Meldingen

@MainActor
@Suite struct ReminderTests {
    let fixture: PartnerFixture
    init() throws { fixture = try PartnerFixture() }

    func plan(_ settings: ReminderSettings, at now: Date? = nil) -> [PlannedReminder] {
        ReminderPlanner.plan(settings, tone: .sweet, now: now ?? fixture.now, timeZone: .gmt) { _ in .hungry }
    }

    @Test func schedulesAtMostTwoPerDay() {
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60, 18 * 60]))
        let perDay = Dictionary(grouping: reminders, by: \.day)
        #expect(perDay.keys.contains(fixture.today.adding(1)))
        #expect(perDay.values.allSatisfy { $0.count <= ReminderSettings.maximumPerDay })
        #expect(perDay[fixture.today.adding(1)]?.map(\.minutes) == [9 * 60, 12 * 60])
    }

    @Test func neverSchedulesAtNight() {
        let reminders = plan(ReminderSettings(isOn: true, times: [22 * 60 + 30, 7 * 60, 21 * 60]))
        #expect(reminders.isEmpty)
        let mixed = plan(ReminderSettings(isOn: true, times: [23 * 60, 13 * 60]))
        #expect(mixed.map(\.minutes).allSatisfy { $0 >= 8 * 60 && $0 < 21 * 60 })
        #expect(!mixed.isEmpty)
    }

    @Test func timesThatHavePassedTodayAreSkipped() {
        // 11:06 UTC: the 09:00 reminder of today is gone, the 12:30 one is still to come.
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60 + 30]))
        #expect(reminders.filter { $0.day == fixture.today }.map(\.minutes) == [12 * 60 + 30])
        #expect(reminders.filter { $0.day == fixture.today.adding(1) }.count == 2)
    }

    @Test func remindersOfOneDayReadDifferently() {
        let reminders = plan(ReminderSettings(isOn: true, times: [9 * 60, 12 * 60]))
        let tomorrow = reminders.filter { $0.day == fixture.today.adding(1) }.map(\.messageKey)
        #expect(Set(tomorrow).count == 2)
        #expect(tomorrow.allSatisfy { $0.hasPrefix("creature.message.hungry.sweet.") })
    }

    @Test func nothingIsScheduledWhenTurnedOff() async {
        #expect(plan(ReminderSettings(isOn: false)).isEmpty)

        let partner = fixture.partner(fixture.profile())
        fixture.creature()
        partner.refresh()
        await partner.setRemindersOn(true)
        #expect(!fixture.delivery.reminders.isEmpty)
        #expect(fixture.delivery.title == "Pip")

        await partner.setRemindersOn(false)
        #expect(fixture.delivery.reminders.isEmpty)
    }

    @Test func refusedPermissionKeepsRemindersOff() async {
        let partner = fixture.partner(fixture.profile())
        fixture.creature()
        partner.refresh()
        fixture.delivery.grantsPermission = false

        await partner.setRemindersOn(true)

        #expect(!partner.reminders.isOn)
        #expect(partner.remindersRefused)
        #expect(fixture.delivery.reminders.isEmpty)
    }

    @Test func settingsAreKeptOnTheDevice() async {
        let profile = fixture.profile()
        fixture.creature()
        let partner = fixture.partner(profile)
        partner.refresh()
        await partner.setRemindersOn(true)
        partner.setReminderTime(at: 1, to: 19 * 60)
        partner.setReminderTime(at: 0, to: 22 * 60)

        let reopened = fixture.partner(profile)
        #expect(reopened.reminders == ReminderSettings(isOn: true, times: [12 * 60 + 30, 19 * 60]))
    }
}
