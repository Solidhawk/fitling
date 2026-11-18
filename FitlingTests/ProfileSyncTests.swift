import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor
@Suite struct ProfileSyncTests {
    let container: ModelContainer
    let userID = UUID()
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    func record(updatedAt: Date, weightKg: Double = 80) -> ProfileRecord {
        let profile = makeLocal(updatedAt: updatedAt, weightKg: weightKg, insert: false)
        return ProfileRecord(profile)
    }

    @discardableResult
    func makeLocal(updatedAt: Date, weightKg: Double = 80, insert: Bool = true) -> UserProfile {
        let profile = UserProfile(
            id: userID,
            healthConsentAt: Date(timeIntervalSince1970: 1_800_000_000),
            healthConsentVersion: 1,
            body: BodyProfile(
                birthDate: BirthDateCalendar.date(from: "1996-01-10")!,
                sex: .male, heightCm: 180, weightKg: weightKg, activityLevel: .moderate, goal: .maintain
            ),
            targets: NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77),
            targetsAreManual: false,
            updatedAt: updatedAt
        )
        if insert { context.insert(profile) }
        return profile
    }

    func makeSync(
        fetch: @escaping @Sendable (UUID) async throws -> ProfileRecord? = { _ in nil },
        upsert: @escaping @Sendable (ProfileRecord) async throws -> Void = { _ in }
    ) -> ProfileSync {
        ProfileSync(context: context, fetchRemote: fetch, upsertRemote: upsert)
    }

    @Test func pullAdoptsRemoteWhenNoLocal() async throws {
        let remote = record(updatedAt: .init(timeIntervalSince1970: 1_800_000_100), weightKg: 72)
        let sync = makeSync(fetch: { _ in remote })
        #expect(try await sync.pull(userID: userID) == .adoptedRemote)
        let local = try #require(sync.localProfile(userID: userID))
        #expect(local.weightKg == 72)
        #expect(local.needsPush == false)
    }

    @Test func pullReportsRemoteMissing() async throws {
        #expect(try await makeSync().pull(userID: userID) == .remoteMissing)
        #expect(makeSync().localProfile(userID: userID) == nil)
    }

    @Test func pullKeepsUnpushedLocalWhenRemoteMissing() async throws {
        makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        #expect(try await makeSync().pull(userID: userID) == .keptLocal)
    }

    @Test func pullKeepsLocalWithPendingPush() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100), weightKg: 80)
        let remote = record(updatedAt: .init(timeIntervalSince1970: 1_800_000_900), weightKg: 60)
        #expect(try await makeSync(fetch: { _ in remote }).pull(userID: userID) == .keptLocal)
        #expect(local.weightKg == 80)
    }

    @Test func pullAdoptsNewerRemote() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100), weightKg: 80)
        local.needsPush = false
        let remote = record(updatedAt: .init(timeIntervalSince1970: 1_800_000_900), weightKg: 60)
        #expect(try await makeSync(fetch: { _ in remote }).pull(userID: userID) == .adoptedRemote)
        #expect(local.weightKg == 60)
    }

    @Test func pullIgnoresOlderRemote() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_900), weightKg: 80)
        local.needsPush = false
        let remote = record(updatedAt: .init(timeIntervalSince1970: 1_800_000_100), weightKg: 60)
        #expect(try await makeSync(fetch: { _ in remote }).pull(userID: userID) == .unchanged)
        #expect(local.weightKg == 80)
    }

    @Test func pullNetworkErrorThrowsNetwork() async {
        let sync = makeSync(fetch: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: SyncError.network) { try await sync.pull(userID: userID) }
    }

    @Test func pushClearsFlagWhenUnchanged() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        try await makeSync().push(userID: userID)
        #expect(local.needsPush == false)
    }

    @Test func pushKeepsFlagWhenEditedDuringPush() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        let container = container
        let sync = makeSync(upsert: { _ in
            await MainActor.run {
                let profile = try? container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
                profile?.updatedAt = Date(timeIntervalSince1970: 1_800_000_200)
            }
        })
        try await sync.push(userID: userID)
        #expect(local.needsPush)
    }

    @Test func pushRejectedKeepsFlagAndReports() async {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        let counter = CallCounter()
        let sync = makeSync(upsert: { _ in
            await counter.increment()
            throw NSError(domain: "postgrest", code: 23514)
        })
        await #expect(throws: SyncError.self) { try await sync.push(userID: userID) }
        #expect(local.needsPush)
        #expect(sync.lastRejection != nil)
        #expect(await counter.count == 1)
    }

    @Test func pushSkipsWhenNothingPending() async throws {
        let local = makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        local.needsPush = false
        let counter = CallCounter()
        try await makeSync(upsert: { _ in await counter.increment() }).push(userID: userID)
        #expect(await counter.count == 0)
    }

    @Test func syncKeepsItsStoreAlive() throws {
        let sync = try { () throws -> ProfileSync in
            let container = try makeModelContainer(inMemory: true)
            return ProfileSync(context: container.mainContext, fetchRemote: { _ in nil }, upsertRemote: { _ in })
        }()
        #expect(sync.localProfile(userID: userID) == nil)
    }

    @Test func deleteLocalDataRemovesProfile() throws {
        makeLocal(updatedAt: .init(timeIntervalSince1970: 1_800_000_100))
        let sync = makeSync()
        try sync.deleteLocalData()
        #expect(sync.localProfile(userID: userID) == nil)
    }
}
