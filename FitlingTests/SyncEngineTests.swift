import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SyncEngineTests {
    let userID = UUID()
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let today = Day(ordinal: 20775)
    let periods = "target_history"

    func makeEngine(_ remote: FakeRemoteStore) throws -> SyncEngine {
        // The container is made here and handed over: nothing but the engine holds it afterwards.
        SyncEngine(
            container: try makeModelContainer(inMemory: true), remote: remote,
            tables: SyncTables.all, now: { [now] in now }
        )
    }

    @discardableResult
    func addPeriod(to engine: SyncEngine, id: UUID = UUID(), kcal: Int = 2000, updatedAt: Date? = nil, needsPush: Bool = true) -> TargetPeriod {
        let period = TargetPeriod(
            id: id, userID: userID, effectiveOn: today,
            targets: NutritionTargets(kcal: kcal, proteinG: 150, carbsG: 200, fatG: 60), updatedAt: updatedAt ?? now
        )
        period.needsPush = needsPush
        engine.context.insert(period)
        return period
    }

    func record(id: UUID = UUID(), kcal: Int = 2000, updatedAt: Date, deletedAt: Date? = nil) -> TargetPeriodRecord {
        TargetPeriodRecord(
            id: id, userID: userID, effectiveOn: today, kcalTarget: kcal, proteinTargetG: 150, carbsTargetG: 200, fatTargetG: 60,
            updatedAt: updatedAt, deletedAt: deletedAt, syncedAt: nil
        )
    }

    func makeProfile() -> UserProfile {
        let body = BodyProfile(
            birthDay: Day(ordinal: 9505), sex: .female, heightCm: 165.5, weightKg: 65.2, activityLevel: .veryActive, goal: .buildMuscle
        )
        let targets = NutritionTargets(kcal: 2400, proteinG: 117, carbsG: 320, fatG: 67)
        return UserProfile(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body, targets: targets, targetsAreManual: true, updatedAt: now
        )
    }

    func storedPeriods(_ engine: SyncEngine) throws -> [TargetPeriod] {
        try engine.context.fetch(FetchDescriptor<TargetPeriod>())
    }

    func cursor(_ engine: SyncEngine, table: String) throws -> Date? {
        try engine.context.fetch(FetchDescriptor<SyncCursor>()).first { $0.table == table }?.syncedAt
    }

    func lastPull(_ engine: SyncEngine, table: String) throws -> Date? {
        try engine.context.fetch(FetchDescriptor<SyncCursor>()).first { $0.table == table }?.pulledAt
    }

    // MARK: Push

    @Test func pushSendsOnlyRowsThatNeedIt() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let waiting = addPeriod(to: engine, kcal: 2100)
        addPeriod(to: engine, needsPush: false)

        #expect(await engine.sync() == .completed)

        #expect(remote.upserts == [FakeRemoteStore.Upsert(table: periods, ids: [waiting.id])])
        #expect(remote.row(waiting.id, in: periods)?["kcal_target"] as? Int == 2100)
        #expect(!waiting.needsPush)
    }

    @Test func pushGoesInTheOrderOfTheTables() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        addPeriod(to: engine)
        engine.context.insert(makeProfile())

        await engine.sync()

        #expect(remote.upserts.map(\.table) == ["profiles", periods])
    }

    @Test func pushSendsRowsInBlocksOfTwoHundred() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        for _ in 0..<201 {
            addPeriod(to: engine)
        }

        await engine.sync()

        #expect(remote.upserts.map(\.ids.count).sorted() == [1, 200])
        #expect(remote.rowCount(in: periods) == 201)
    }

    @Test func pushKeepsTheFlagWhenTheRowChangedMeanwhile() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine, kcal: 2000)
        let later = now.addingTimeInterval(30)
        remote.duringUpsert = {
            period.kcalTarget = 2100
            period.updatedAt = later
        }

        await engine.sync()

        #expect(remote.row(period.id, in: periods)?["kcal_target"] as? Int == 2000)
        #expect(period.needsPush)
        // The pull that followed brought back the version that was sent; the newer change stays.
        #expect(period.kcalTarget == 2100)

        await engine.sync()

        #expect(remote.row(period.id, in: periods)?["kcal_target"] as? Int == 2100)
        #expect(!period.needsPush)
    }

    @Test func pushRemovesARowLocallyOnceItsDeletionIsOnTheServer() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine)
        let id = period.id
        period.deletedAt = now

        await engine.sync()

        #expect(remote.row(id, in: periods)?["deleted_at"] is Double)
        #expect(try storedPeriods(engine).isEmpty)
    }

    @Test func aRejectedRowDoesNotBlockTheOthers() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let first = addPeriod(to: engine)
        let refused = addPeriod(to: engine)
        let last = addPeriod(to: engine)
        remote.rejectedIDs = [refused.id]

        #expect(await engine.sync() == .completed)

        #expect(remote.row(first.id, in: periods) != nil)
        #expect(remote.row(last.id, in: periods) != nil)
        #expect(remote.row(refused.id, in: periods) == nil)
        #expect(!first.needsPush)
        #expect(!last.needsPush)
        #expect(refused.needsPush)
        #expect(engine.problemKey == "profile.sync.rejected")

        remote.rejectedIDs = []
        await engine.sync()

        #expect(remote.row(refused.id, in: periods) != nil)
        #expect(engine.problemKey == nil)
    }

    @Test func anOfflineRoundKeepsEverythingForLater() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine)
        remote.isOffline = true

        #expect(await engine.sync() == .offline)

        #expect(period.needsPush)
        #expect(engine.problemKey == nil)
        // The round stops at the first request that fails.
        #expect(remote.upserts.count == 1)
        #expect(remote.fetches.isEmpty)

        remote.isOffline = false
        #expect(await engine.sync() == .completed)
        #expect(!period.needsPush)
    }

    @Test func aRefusedReadEndsTheRoundAsFailed() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine)
        remote.refusesReads = true

        #expect(await engine.sync() == .failed)

        // What was sent before the read failed stays sent.
        #expect(!period.needsPush)
        #expect(engine.problemKey == "error.server")
        #expect(remote.fetches.count == 1)

        remote.refusesReads = false
        #expect(await engine.sync() == .completed)
        #expect(engine.problemKey == nil)
    }

    // MARK: Pull

    @Test func pullAddsNewRowsAndMovesTheCursor() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let earlier = now.addingTimeInterval(-120)
        let latest = now.addingTimeInterval(-60)
        try remote.serve(record(kcal: 1800, updatedAt: earlier), table: periods, syncedAt: earlier)
        try remote.serve(record(kcal: 1900, updatedAt: latest), table: periods, syncedAt: latest)

        try await engine.pull(TargetPeriod.self)

        let stored = try storedPeriods(engine)
        #expect(stored.map(\.kcalTarget).sorted() == [1800, 1900])
        #expect(stored.allSatisfy { !$0.needsPush && $0.userID == userID && $0.effectiveOn == today.isoString })
        #expect(try cursor(engine, table: periods) == latest)
        #expect(try lastPull(engine, table: periods) == now)
    }

    @Test func pullOfAnEmptyTableRemembersThatItHappened() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)

        try await engine.pull(TargetPeriod.self)
        try await engine.pull(TargetPeriod.self)

        #expect(remote.fetches == Array(repeating: FakeRemoteStore.Fetch(table: periods, since: nil, offset: 0), count: 2))
        #expect(try cursor(engine, table: periods) == nil)
        #expect(try lastPull(engine, table: periods) == now)
    }

    @Test func pullReadsEveryPage() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        for index in 0..<501 {
            try remote.serve(record(updatedAt: now), table: periods, syncedAt: now.addingTimeInterval(Double(index)))
        }

        try await engine.pull(TargetPeriod.self)

        #expect(remote.fetches.map(\.offset) == [0, 500])
        #expect(try storedPeriods(engine).count == 501)
        #expect(try cursor(engine, table: periods) == now.addingTimeInterval(500))
    }

    /// The rows come newest first. A row that another device changes while the pages are read
    /// moves to the front: this pull misses it, the cursor stays behind it, the next pull has it.
    @Test func aRowThatChangesWhilePagesAreReadArrivesWithTheNextPull() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let start = now.addingTimeInterval(-7200)
        let oldest = record(kcal: 1500, updatedAt: start)
        try remote.serve(oldest, table: periods, syncedAt: start)
        for index in 1...500 {
            try remote.serve(record(updatedAt: start), table: periods, syncedAt: start.addingTimeInterval(Double(index)))
        }
        remote.afterFirstFetch = { [self] in
            try? remote.serve(record(id: oldest.id, kcal: 1900, updatedAt: now), table: periods, syncedAt: now)
        }

        try await engine.pull(TargetPeriod.self)

        #expect(try cursor(engine, table: periods) == start.addingTimeInterval(500))
        #expect(try storedPeriods(engine).count == 500)

        try await engine.pull(TargetPeriod.self)

        let stored = try storedPeriods(engine)
        #expect(stored.count == 501)
        #expect(stored.first { $0.id == oldest.id }?.kcalTarget == 1900)
        #expect(try cursor(engine, table: periods) == now)
    }

    @Test func pullKeepsANewerLocalChange() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine, kcal: 2100, updatedAt: now)
        let older = now.addingTimeInterval(-60)
        try remote.serve(record(id: period.id, kcal: 1800, updatedAt: older), table: periods, syncedAt: older)

        try await engine.pull(TargetPeriod.self)

        #expect(period.kcalTarget == 2100)
        #expect(period.needsPush)
        #expect(try storedPeriods(engine).count == 1)
        #expect(try cursor(engine, table: periods) == older)
    }

    @Test func pullOverwritesAnOlderLocalRow() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let older = now.addingTimeInterval(-60)
        let sent = addPeriod(to: engine, kcal: 2000, updatedAt: older, needsPush: false)
        let waiting = addPeriod(to: engine, kcal: 2000, updatedAt: older, needsPush: true)
        try remote.serve(record(id: sent.id, kcal: 1800, updatedAt: now), table: periods, syncedAt: now)
        try remote.serve(record(id: waiting.id, kcal: 1700, updatedAt: now), table: periods, syncedAt: now)

        try await engine.pull(TargetPeriod.self)

        #expect(sent.kcalTarget == 1800)
        #expect(sent.updatedAt == now)
        #expect(waiting.kcalTarget == 1700)
        #expect(!waiting.needsPush)
        #expect(try storedPeriods(engine).count == 2)
    }

    @Test func pullRemovesRowsTheServerMarkedDeleted() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let period = addPeriod(to: engine, updatedAt: now.addingTimeInterval(-60), needsPush: false)
        addPeriod(to: engine, needsPush: false)
        try remote.serve(record(id: period.id, updatedAt: now, deletedAt: now), table: periods, syncedAt: now)
        // A deletion of a row this device never had.
        try remote.serve(record(updatedAt: now, deletedAt: now), table: periods, syncedAt: now)

        try await engine.pull(TargetPeriod.self)

        #expect(try storedPeriods(engine).count == 1)
        #expect(try cursor(engine, table: periods) == now)
    }

    @Test func pullAsksAgainFromFiveMinutesBeforeTheCursor() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let lastSeen = now.addingTimeInterval(-3600)
        engine.context.insert(SyncCursor(table: periods, syncedAt: lastSeen, pulledAt: lastSeen))

        try await engine.pull(TargetPeriod.self)

        #expect(remote.fetches == [FakeRemoteStore.Fetch(table: periods, since: lastSeen.addingTimeInterval(-300), offset: 0)])
        #expect(try cursor(engine, table: periods) == lastSeen)
        #expect(try lastPull(engine, table: periods) == now)
    }

    @Test func aQuietTableIsNotClearedWhileTheDeviceKeepsPulling() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let longAgo = now.addingTimeInterval(-200 * 24 * 60 * 60)
        engine.context.insert(SyncCursor(table: periods, syncedAt: longAgo, pulledAt: now.addingTimeInterval(-24 * 60 * 60)))
        addPeriod(to: engine, updatedAt: longAgo, needsPush: false)

        try await engine.pull(TargetPeriod.self)

        #expect(remote.fetches == [FakeRemoteStore.Fetch(table: periods, since: longAgo.addingTimeInterval(-300), offset: 0)])
        #expect(try storedPeriods(engine).count == 1)
    }

    @Test func oldCursorClearsTheTableAndPullsEverything() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let longAgo = now.addingTimeInterval(-91 * 24 * 60 * 60)
        engine.context.insert(SyncCursor(table: periods, syncedAt: longAgo, pulledAt: longAgo))
        // Deleted on another device; the server has already cleaned up the marker.
        addPeriod(to: engine, kcal: 1500, updatedAt: longAgo, needsPush: false)
        let stillThere = addPeriod(to: engine, kcal: 1600, updatedAt: longAgo, needsPush: false)
        let waiting = addPeriod(to: engine, kcal: 1700, needsPush: true)
        try remote.serve(record(id: stillThere.id, kcal: 1650, updatedAt: longAgo), table: periods, syncedAt: longAgo)
        try remote.serve(record(kcal: 1800, updatedAt: now), table: periods, syncedAt: now)

        try await engine.pull(TargetPeriod.self)

        #expect(remote.fetches == [FakeRemoteStore.Fetch(table: periods, since: nil, offset: 0)])
        #expect(try storedPeriods(engine).map(\.kcalTarget).sorted() == [1650, 1700, 1800])
        #expect(try storedPeriods(engine).contains { $0.id == waiting.id && $0.needsPush })
        #expect(try cursor(engine, table: periods) == now)
    }

    // MARK: Rounds

    @Test func onlyOneRoundRunsAtATime() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        addPeriod(to: engine)
        remote.holdsNextRequest = true

        let first = Task { await engine.sync() }
        try #require(await remote.requestArrived())
        let second = Task { await engine.sync() }
        let third = Task { await engine.sync() }
        // Both calls reach the engine while the first round is still waiting on the server.
        for _ in 0..<100 {
            await Task.yield()
        }
        remote.releaseRequest()

        #expect(await first.value == .completed)
        #expect(await second.value == .completed)
        #expect(await third.value == .completed)
        #expect(remote.upserts.count == 1)
        // The two calls during the round were answered by one more round, not by two.
        #expect(remote.fetches.filter { $0.table == periods }.count == 2)
    }

    @Test func erasingDuringARoundKeepsNothingFromIt() async throws {
        let remote = FakeRemoteStore()
        try remote.serve(record(kcal: 1800, updatedAt: now), table: periods, syncedAt: now)
        let engine = try makeEngine(remote)
        addPeriod(to: engine)
        remote.holdsNextRequest = true

        let round = Task { await engine.sync() }
        try #require(await remote.requestArrived())
        engine.eraseLocalData()
        remote.releaseRequest()

        #expect(await round.value == .interrupted)
        #expect(try storedPeriods(engine).isEmpty)
        #expect(try engine.context.fetch(FetchDescriptor<SyncCursor>()).isEmpty)
        #expect(remote.fetches.isEmpty)
    }

    /// A call that waited on the interrupted round must not start a round of its own: the
    /// session it was meant for has just ended.
    @Test func erasingDuringARoundAlsoAnswersTheCallersWaitingOnIt() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        addPeriod(to: engine)
        remote.holdsNextRequest = true

        let round = Task { await engine.sync() }
        try #require(await remote.requestArrived())
        let waiting = Task { await engine.sync() }
        for _ in 0..<100 {
            await Task.yield()
        }
        engine.eraseLocalData()
        remote.releaseRequest()

        #expect(await round.value == .interrupted)
        #expect(await waiting.value == .interrupted)
        #expect(remote.fetches.isEmpty)
        #expect(engine.problemKey == nil)
    }

    @Test func eraseRemovesEveryKindOfLocalData() throws {
        let engine = try makeEngine(FakeRemoteStore())
        engine.context.insert(makeProfile())
        addPeriod(to: engine)
        engine.context.insert(SyncCursor(table: periods, syncedAt: now, pulledAt: now))
        engine.context.insert(DayActivity(day: today, workoutKcal: 300, updatedAt: now))
        #expect(engine.hasUnsentChanges)

        engine.eraseLocalData()

        #expect(try engine.context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        #expect(try storedPeriods(engine).isEmpty)
        #expect(try engine.context.fetch(FetchDescriptor<SyncCursor>()).isEmpty)
        #expect(try engine.context.fetch(FetchDescriptor<DayActivity>()).isEmpty)
        #expect(!engine.hasUnsentChanges)
    }

    @Test func unsentChangesAreSeenInEveryTable() throws {
        let engine = try makeEngine(FakeRemoteStore())
        #expect(!engine.hasUnsentChanges)
        addPeriod(to: engine, needsPush: false)
        #expect(!engine.hasUnsentChanges)
        let profile = makeProfile()
        engine.context.insert(profile)
        #expect(engine.hasUnsentChanges)
        profile.needsPush = false
        addPeriod(to: engine, needsPush: true)
        #expect(engine.hasUnsentChanges)
    }

    @Test func engineKeepsItsStoreAlive() async throws {
        let remote = FakeRemoteStore()
        try remote.serve(record(kcal: 1800, updatedAt: now), table: periods, syncedAt: now)
        let engine = try makeEngine(remote)

        #expect(await engine.sync() == .completed)

        #expect(try storedPeriods(engine).map(\.kcalTarget) == [1800])
    }

    @Test func aProfileTravelsToTheServerAndToAnotherDevice() async throws {
        let remote = FakeRemoteStore()
        let phone = try makeEngine(remote)
        let profile = makeProfile()
        profile.postalCode = "3511 AB"
        profile.countsWorkoutEnergy = true
        phone.context.insert(profile)
        await phone.sync()

        let tablet = try makeEngine(remote)
        await tablet.sync()

        let received = try #require(try tablet.context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(received.id == userID)
        #expect(received.bodyProfile == profile.bodyProfile)
        #expect(received.targets == profile.targets)
        #expect(received.healthConsentAt == now)
        #expect(received.targetsAreManual)
        #expect(received.countsWorkoutEnergy)
        #expect(received.postalCode == "3511 AB")
        #expect(!received.needsPush)
    }

    @Test func aClearedPostalCodeIsClearedOnTheServerToo() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let profile = makeProfile()
        profile.postalCode = "3511 AB"
        engine.context.insert(profile)
        await engine.sync()
        #expect(remote.row(userID, in: "profiles")?["postal_code"] as? String == "3511 AB")

        profile.postalCode = nil
        profile.updatedAt = now.addingTimeInterval(60)
        profile.needsPush = true
        await engine.sync()

        #expect(remote.row(userID, in: "profiles")?["postal_code"] is NSNull)
        #expect(profile.postalCode == nil)
    }
}
