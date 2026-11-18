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
struct FlowFixture {
    let container: ModelContainer
    let userID = UUID()
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    @discardableResult
    func insertProfile(needsPush: Bool = false, manualTargets: Bool = false, insert: Bool = true) -> UserProfile {
        let profile = UserProfile(
            id: userID,
            healthConsentAt: Date(timeIntervalSince1970: 1_800_000_000),
            healthConsentVersion: 1,
            body: BodyProfile(
                birthDate: BirthDateCalendar.date(from: "1996-01-10")!,
                sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain
            ),
            targets: NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77),
            targetsAreManual: manualTargets,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        profile.needsPush = needsPush
        if insert { context.insert(profile) }
        return profile
    }

    func sync(
        fetch: @escaping @Sendable (UUID) async throws -> ProfileRecord? = { _ in nil },
        upsert: @escaping @Sendable (ProfileRecord) async throws -> Void = { _ in }
    ) -> ProfileSync {
        ProfileSync(context: context, fetchRemote: fetch, upsertRemote: upsert)
    }
}

@MainActor
@Suite struct RootViewModelTests {
    let fixture: FlowFixture
    init() throws { fixture = try FlowFixture() }

    @Test(.timeLimit(.minutes(1))) func signedOutShowsWelcome() async {
        let root = RootViewModel(auth: FakeAuthProvider(state: .signedOut), sync: fixture.sync())
        await root.refresh()
        #expect(root.screen == .welcome)
    }

    @Test func verificationShowsVerifyScreen() async {
        let root = RootViewModel(auth: FakeAuthProvider(state: .awaitingEmailVerification(email: "a@example.test")), sync: fixture.sync())
        await root.refresh()
        #expect(root.screen == .verifyEmail("a@example.test"))
    }

    @Test func firstDeviceOnlineNoRemoteGoesToOnboarding() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let root = RootViewModel(auth: auth, sync: fixture.sync())
        await root.refresh()
        #expect(root.screen == .onboarding(fixture.userID))
    }

    @Test func firstDeviceOnlineWithRemoteGoesHome() async {
        let remote = ProfileRecord(fixture.insertProfile(insert: false))
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync(fetch: { _ in remote })
        let root = RootViewModel(auth: auth, sync: sync)
        await root.refresh()
        #expect(root.screen == .home(fixture.userID))
        #expect(sync.localProfile(userID: fixture.userID) != nil)
    }

    @Test func firstDeviceOfflineShowsNeedsConnection() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync(fetch: { _ in throw URLError(.notConnectedToInternet) })
        let root = RootViewModel(auth: auth, sync: sync)
        await root.refresh()
        #expect(root.screen == .needsConnection)
        #expect(sync.localProfile(userID: fixture.userID) == nil)
    }

    @Test func existingLocalProfileGoesHomeEvenOffline() async {
        fixture.insertProfile(needsPush: true)
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync(
            fetch: { _ in throw URLError(.notConnectedToInternet) },
            upsert: { _ in throw URLError(.notConnectedToInternet) }
        )
        let root = RootViewModel(auth: auth, sync: sync)
        await root.refresh()
        #expect(root.screen == .home(fixture.userID))
    }

    @Test func urlBeforeAuthReadyIsHandledAfterwards() async {
        let auth = FakeAuthProvider(state: .loading)
        let root = RootViewModel(auth: auth, sync: fixture.sync())
        await root.open(URL(string: "fitling://auth-callback?code=abc")!)
        #expect(auth.calls["handle"] == nil)
        auth.state = .signedOut
        await root.refresh()
        #expect(auth.calls["handle"] == 1)
    }

    @Test func recoveryLinkShowsPasswordReset() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        auth.nextLink = .passwordRecovery
        let root = RootViewModel(auth: auth, sync: fixture.sync())
        await root.open(URL(string: "fitling://reset-password?code=abc")!)
        #expect(root.showsPasswordReset)
    }

    @Test func foreignLinkIsExplained() async {
        let auth = FakeAuthProvider(state: .signedOut)
        auth.nextError["handle"] = .invalidOrForeignLink
        let root = RootViewModel(auth: auth, sync: fixture.sync())
        await root.open(URL(string: "fitling://reset-password?code=abc")!)
        #expect(root.linkMessageKey == "auth.reset.linkInvalid")
    }

    @Test func onboardingFinishedGoesHomeAndPushes() async {
        let counter = CallCounter()
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let root = RootViewModel(auth: auth, sync: fixture.sync(upsert: { _ in await counter.increment() }))
        let profile = fixture.insertProfile(needsPush: true)
        await root.onboardingFinished(profile)
        #expect(root.screen == .home(fixture.userID))
        #expect(await counter.count == 1)
    }
}

@MainActor
@Suite struct ProfileViewModelTests {
    let fixture: FlowFixture
    let now = BirthDateCalendar.date(from: "2026-11-18")!
    init() throws { fixture = try FlowFixture() }

    func makeViewModel(_ profile: UserProfile) -> ProfileViewModel {
        let now = now
        return ProfileViewModel(profile: profile, sync: fixture.sync(), now: { now })
    }

    @Test func editingProfileRecalculatesAutoTargets() {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        var body = profile.bodyProfile
        body.weightKg = 90
        #expect(viewModel.saveProfile(body) == .saved)
        #expect(profile.weightKg == 90)
        #expect(profile.targets == calculateEnergy(for: body, on: now, calendar: BirthDateCalendar.calendar).targets)
        #expect(profile.needsPush)
        #expect(profile.updatedAt == now)
    }

    @Test func editingProfileWithManualTargetsAsks() {
        let profile = fixture.insertProfile(manualTargets: true)
        let viewModel = makeViewModel(profile)
        var body = profile.bodyProfile
        body.weightKg = 90
        #expect(viewModel.saveProfile(body) == .askRecalculate)
        #expect(profile.kcalTarget == 2760)
        viewModel.recalculateTargets()
        #expect(profile.targetsAreManual == false)
        #expect(profile.kcalTarget != 2760)
    }

    @Test func saveTargetsOutOfRangeThrows() {
        let viewModel = makeViewModel(fixture.insertProfile())
        #expect(throws: ProfileViewModel.TargetsError.outOfRange(field: "kcal")) {
            try viewModel.saveTargets(NutritionTargets(kcal: 0, proteinG: 100, carbsG: 200, fatG: 60))
        }
        #expect(throws: ProfileViewModel.TargetsError.outOfRange(field: "protein")) {
            try viewModel.saveTargets(NutritionTargets(kcal: 2000, proteinG: 1001, carbsG: 200, fatG: 60))
        }
    }

    @Test func saveTargetsMarksManualAndPending() throws {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        try viewModel.saveTargets(NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70))
        #expect(profile.targets == NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70))
        #expect(profile.targetsAreManual)
        #expect(profile.needsPush)
    }

    @Test func lowTargetWarns() throws {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        #expect(viewModel.isBelowSafeMinimum == false)
        try viewModel.saveTargets(NutritionTargets(kcal: 1400, proteinG: 120, carbsG: 120, fatG: 40))
        #expect(viewModel.isBelowSafeMinimum)
    }
}

@MainActor
@Suite struct AccountViewModelTests {
    let fixture: FlowFixture
    init() throws { fixture = try FlowFixture() }

    @Test func signOutOfflineWithPendingWarns() async {
        fixture.insertProfile(needsPush: true)
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync(upsert: { _ in throw URLError(.notConnectedToInternet) })
        let viewModel = AccountViewModel(auth: auth, sync: sync, userID: fixture.userID, usesApple: false)
        #expect(await viewModel.signOut(force: false) == .unsyncedChanges)
        #expect(auth.calls["signOut"] == nil)
        #expect(sync.localProfile(userID: fixture.userID) != nil)
    }

    @Test func signOutForceWipesLocal() async {
        fixture.insertProfile(needsPush: true)
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync(upsert: { _ in throw URLError(.notConnectedToInternet) })
        let viewModel = AccountViewModel(auth: auth, sync: sync, userID: fixture.userID, usesApple: false)
        #expect(await viewModel.signOut(force: true) == .signedOut)
        #expect(auth.calls["signOut"] == 1)
        #expect(sync.localProfile(userID: fixture.userID) == nil)
    }

    @Test func deleteAccountAppleSendsCode() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: true))
        let viewModel = AccountViewModel(auth: auth, sync: fixture.sync(), userID: fixture.userID, usesApple: true)
        await viewModel.deleteAccount(appleAuthorizationCode: "code-123")
        #expect(auth.lastAppleAuthorizationCode == .some("code-123"))
    }

    @Test func deleteAccountEmailSendsNil() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let viewModel = AccountViewModel(auth: auth, sync: fixture.sync(), userID: fixture.userID, usesApple: false)
        await viewModel.deleteAccount(appleAuthorizationCode: nil)
        #expect(auth.lastAppleAuthorizationCode == .some(nil))
    }

    @Test func deleteAccountDoubleTapCallsOnce() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let viewModel = AccountViewModel(auth: auth, sync: fixture.sync(), userID: fixture.userID, usesApple: false)
        await expectSingleCall("deleteAccount", on: auth) { await viewModel.deleteAccount(appleAuthorizationCode: nil) }
    }

    @Test func deleteAccountWipesLocalData() async {
        fixture.insertProfile()
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        let sync = fixture.sync()
        let viewModel = AccountViewModel(auth: auth, sync: sync, userID: fixture.userID, usesApple: false)
        await viewModel.deleteAccount(appleAuthorizationCode: nil)
        #expect(sync.localProfile(userID: fixture.userID) == nil)
    }

    @Test func failedDeleteKeepsDataAndExplains() async {
        fixture.insertProfile()
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: false))
        auth.nextError["deleteAccount"] = .network
        let sync = fixture.sync()
        let viewModel = AccountViewModel(auth: auth, sync: sync, userID: fixture.userID, usesApple: false)
        await viewModel.deleteAccount(appleAuthorizationCode: nil)
        #expect(viewModel.messageKey == "error.network")
        #expect(sync.localProfile(userID: fixture.userID) != nil)
    }
}
