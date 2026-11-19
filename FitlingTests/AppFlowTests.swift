import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
struct FlowFixture {
    let container: ModelContainer
    let remote: FakeRemoteStore
    let sync: SyncEngine
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    var context: ModelContext { sync.context }
    var today: Day { Day(now, timeZone: .gmt) }

    init() throws {
        container = try makeModelContainer(inMemory: true)
        remote = FakeRemoteStore()
        sync = SyncEngine(container: container, remote: remote, tables: SyncTables.all, now: { [now] in now })
    }

    var body: BodyProfile {
        BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
    }

    func makeProfile(needsPush: Bool = false, manualTargets: Bool = false) -> UserProfile {
        let profile = UserProfile(
            id: userID,
            healthConsentAt: now.addingTimeInterval(-86_400),
            healthConsentVersion: 1,
            body: body,
            targets: NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77),
            targetsAreManual: manualTargets,
            updatedAt: now.addingTimeInterval(-3_600)
        )
        profile.needsPush = needsPush
        return profile
    }

    @discardableResult
    func insertProfile(needsPush: Bool = false, manualTargets: Bool = false) -> UserProfile {
        let profile = makeProfile(needsPush: needsPush, manualTargets: manualTargets)
        context.insert(profile)
        try? context.save()
        return profile
    }

    func root(_ state: AuthState) -> (RootViewModel, FakeAuthProvider) {
        let auth = FakeAuthProvider(state: state)
        return (RootViewModel(auth: auth, sync: sync, food: FoodServices(source: FakeProductSource(), search: FakeProductSearch())), auth)
    }

    var signedIn: AuthState { .signedIn(userID: userID, usesApple: false) }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct RootViewModelTests {
    let fixture: FlowFixture
    init() throws { fixture = try FlowFixture() }

    @Test func signedOutWipesLocalData() async {
        fixture.insertProfile()
        let (root, _) = fixture.root(.signedOut)
        await root.refresh()
        #expect(fixture.context.profile(of: fixture.userID) == nil)
    }

    @Test func signedOutShowsWelcome() async {
        let (root, _) = fixture.root(.signedOut)
        await root.refresh()
        #expect(root.screen == .welcome)
    }

    @Test func verificationShowsVerifyScreen() async {
        let (root, _) = fixture.root(.awaitingEmailVerification(email: "a@example.test"))
        await root.refresh()
        #expect(root.screen == .verifyEmail("a@example.test"))
    }

    @Test func firstDeviceOnlineNoRemoteGoesToOnboarding() async {
        let (root, _) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .onboarding(fixture.userID))
    }

    @Test func firstDeviceOnlineWithRemoteGoesHome() async throws {
        try fixture.remote.serve(fixture.makeProfile().record, table: "profiles", syncedAt: fixture.now)
        let (root, _) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .home(fixture.userID))
        #expect(fixture.context.profile(of: fixture.userID)?.bodyProfile == fixture.body)
    }

    @Test func firstDeviceOfflineShowsNeedsConnection() async {
        fixture.remote.isOffline = true
        let (root, _) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .needsConnection)
        #expect(fixture.context.profile(of: fixture.userID) == nil)
    }

    @Test func existingLocalProfileGoesHomeEvenOffline() async {
        fixture.insertProfile(needsPush: true)
        fixture.remote.isOffline = true
        let (root, _) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .home(fixture.userID))
    }

    @Test func onboardingSurvivesFailedPull() async {
        let (root, _) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .onboarding(fixture.userID))
        fixture.remote.isOffline = true
        await root.refresh()
        #expect(root.screen == .onboarding(fixture.userID))
    }

    @Test func underageDeletionClosesWhenSignedOut() async {
        let (root, auth) = fixture.root(fixture.signedIn)
        root.requestUnderageDeletion(userID: fixture.userID)
        #expect(root.underageDeletion?.id == fixture.userID)
        auth.state = .signedOut
        await root.refresh()
        #expect(root.underageDeletion == nil)
    }

    @Test func urlBeforeAuthReadyIsHandledAfterwards() async {
        let (root, auth) = fixture.root(.loading)
        await root.open(URL(string: "fitling://auth-callback?code=abc")!)
        #expect(auth.calls["handle"] == nil)
        auth.state = .signedOut
        await root.refresh()
        #expect(auth.calls["handle"] == 1)
    }

    @Test func recoveryLinkShowsPasswordReset() async {
        let (root, auth) = fixture.root(fixture.signedIn)
        auth.nextLink = .passwordRecovery
        await root.open(URL(string: "fitling://reset-password?code=abc")!)
        #expect(root.showsPasswordReset)
    }

    @Test func foreignLinkIsExplained() async {
        let (root, auth) = fixture.root(.signedOut)
        auth.nextError["handle"] = .invalidOrForeignLink
        await root.open(URL(string: "fitling://reset-password?code=abc")!)
        #expect(root.linkMessageKey == "auth.reset.linkInvalid")
    }

    @Test func expiredLinkAsksForANewOne() async {
        let (root, auth) = fixture.root(.signedOut)
        auth.nextError["handle"] = .expiredLink
        await root.open(URL(string: "fitling://reset-password?error_code=otp_expired")!)
        #expect(root.linkMessageKey == "auth.reset.linkExpired")
    }

    @Test func onboardingFinishedGoesHomeAndPushes() async {
        let (root, _) = fixture.root(fixture.signedIn)
        let profile = fixture.insertProfile(needsPush: true)
        await root.onboardingFinished(profile)
        #expect(root.screen == .home(fixture.userID))
        #expect(fixture.remote.row(fixture.userID, in: "profiles") != nil)
        #expect(!profile.needsPush)
    }

    @Test func olderRefreshDoesNotOverwriteANewerOne() async throws {
        let (root, auth) = fixture.root(fixture.signedIn)
        fixture.remote.holdsNextRequest = true
        let first = Task { await root.refresh() }
        try #require(await fixture.remote.requestArrived())

        auth.state = .signedOut
        await root.refresh()
        #expect(root.screen == .welcome)

        fixture.remote.releaseRequest()
        await first.value
        #expect(root.screen == .welcome)
    }

    @Test func signOutGoesStraightToWelcome() async {
        fixture.insertProfile()
        let (root, auth) = fixture.root(fixture.signedIn)
        await root.refresh()
        #expect(root.screen == .home(fixture.userID))

        fixture.remote.isOffline = true
        let account = AccountViewModel(auth: auth, sync: fixture.sync, usesApple: false)
        #expect(await account.signOut(force: true) == .signedOut)
        // Until the root reacts, the profile screen still has its profile: there is no moment in
        // which it has nothing to show and falls back to another screen.
        #expect(fixture.context.profile(of: fixture.userID) != nil)

        await root.refresh()
        #expect(root.screen == .welcome)
        #expect(fixture.context.profile(of: fixture.userID) == nil)
    }

    @Test func deletedAccountLeavesNoDataBehind() async {
        fixture.insertProfile()
        let (root, auth) = fixture.root(fixture.signedIn)
        await root.refresh()
        let account = AccountViewModel(auth: auth, sync: fixture.sync, usesApple: false)
        await account.deleteAccount(appleAuthorizationCode: nil)
        await root.refresh()
        #expect(root.screen == .welcome)
        #expect(fixture.context.profile(of: fixture.userID) == nil)
    }
}

@MainActor
@Suite struct ProfileViewModelTests {
    let fixture: FlowFixture
    init() throws { fixture = try FlowFixture() }

    func makeViewModel(_ profile: UserProfile) -> ProfileViewModel {
        let now = fixture.now
        return ProfileViewModel(profile: profile, sync: fixture.sync, timeZone: .gmt, now: { now })
    }

    func periods() throws -> [TargetPeriod] {
        try fixture.context.fetch(FetchDescriptor<TargetPeriod>()).sorted { $0.effectiveOn < $1.effectiveOn }
    }

    @Test func editingProfileRecalculatesAutoTargets() throws {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        var body = try #require(profile.bodyProfile)
        body.weightKg = 90
        #expect(viewModel.saveProfile(body) == .saved)
        #expect(profile.weightKg == 90)
        #expect(profile.targets == NutritionEngine.plan(for: body, on: fixture.today).targets)
        #expect(profile.needsPush)
        #expect(profile.updatedAt == fixture.now)
    }

    @Test func editingTheProfileWithoutNewTargetsAddsNoPeriod() throws {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        var body = try #require(profile.bodyProfile)
        // A week later in the same year of life: the targets stay exactly the same.
        body.birthDay = body.birthDay.adding(-7)
        #expect(viewModel.saveProfile(body) == .saved)
        #expect(profile.birthDate == body.birthDay.isoString)
        #expect(try periods().isEmpty)
    }

    @Test func editingProfileWithManualTargetsAsks() throws {
        let profile = fixture.insertProfile(manualTargets: true)
        let viewModel = makeViewModel(profile)
        var body = try #require(profile.bodyProfile)
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
        let viewModel = makeViewModel(fixture.insertProfile())
        #expect(viewModel.warnings.isEmpty)
        try viewModel.saveTargets(NutritionTargets(kcal: 1400, proteinG: 120, carbsG: 120, fatG: 40))
        #expect(viewModel.warnings.contains(.belowCommonMinimum))
    }

    @Test func changingTargetsStartsANewPeriodToday() throws {
        let profile = fixture.insertProfile()
        let earlier = TargetPeriod(id: UUID(), userID: fixture.userID, effectiveOn: fixture.today.adding(-10), targets: profile.targets, updatedAt: fixture.now.addingTimeInterval(-864_000))
        earlier.needsPush = false
        fixture.context.insert(earlier)
        let viewModel = makeViewModel(profile)

        try viewModel.saveTargets(NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70))

        let stored = try periods()
        #expect(stored.map(\.effectiveOn) == [fixture.today.adding(-10).isoString, fixture.today.isoString])
        #expect(stored.map(\.kcalTarget) == [2760, 2500])
        #expect(stored.map(\.needsPush) == [false, true])
    }

    @Test func changingTargetsTwiceOnOneDayKeepsOnePeriod() throws {
        let viewModel = makeViewModel(fixture.insertProfile())
        try viewModel.saveTargets(NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70))
        try viewModel.saveTargets(NutritionTargets(kcal: 2400, proteinG: 150, carbsG: 280, fatG: 70))

        let stored = try periods()
        #expect(stored.count == 1)
        #expect(stored.first?.kcalTarget == 2400)
        #expect(stored.first?.effectiveOn == fixture.today.isoString)
    }

    @Test func manualTargetBelowTheFloorWarnsButSaves() throws {
        let profile = fixture.insertProfile()
        let viewModel = makeViewModel(profile)
        try viewModel.saveTargets(NutritionTargets(kcal: 1000, proteinG: 120, carbsG: 60, fatG: 30))
        #expect(profile.kcalTarget == 1000)
        #expect(viewModel.warnings.contains(.belowFloor))
    }

    @Test func editSavesImmediately() throws {
        let viewModel = makeViewModel(fixture.insertProfile())
        try viewModel.saveTargets(NutritionTargets(kcal: 2500, proteinG: 150, carbsG: 300, fatG: 70))

        // Read through another context: only what was saved is there.
        let other = ModelContext(fixture.container)
        #expect(try other.fetch(FetchDescriptor<UserProfile>()).first?.kcalTarget == 2500)
        #expect(try other.fetch(FetchDescriptor<TargetPeriod>()).count == 1)
    }
}

@MainActor
@Suite struct AccountViewModelTests {
    let fixture: FlowFixture
    init() throws { fixture = try FlowFixture() }

    func makeViewModel(_ auth: FakeAuthProvider, usesApple: Bool = false) -> AccountViewModel {
        AccountViewModel(auth: auth, sync: fixture.sync, usesApple: usesApple)
    }

    @Test func signOutOfflineWithPendingWarns() async {
        fixture.insertProfile(needsPush: true)
        fixture.remote.isOffline = true
        let auth = FakeAuthProvider(state: fixture.signedIn)
        #expect(await makeViewModel(auth).signOut(force: false) == .unsyncedChanges)
        #expect(auth.calls["signOut"] == nil)
        #expect(fixture.context.profile(of: fixture.userID) != nil)
    }

    @Test func signOutSendsPendingChangesFirst() async {
        fixture.insertProfile(needsPush: true)
        let auth = FakeAuthProvider(state: fixture.signedIn)
        #expect(await makeViewModel(auth).signOut(force: false) == .signedOut)
        #expect(fixture.remote.row(fixture.userID, in: "profiles") != nil)
        #expect(auth.calls["signOut"] == 1)
    }

    @Test func signOutForceSignsOutWithUnsentChanges() async {
        fixture.insertProfile(needsPush: true)
        fixture.remote.isOffline = true
        let auth = FakeAuthProvider(state: fixture.signedIn)
        #expect(await makeViewModel(auth).signOut(force: true) == .signedOut)
        #expect(auth.calls["signOut"] == 1)
    }

    @Test func offlineSignOutAfterClearingSessionStillSignsOut() async {
        let auth = FakeAuthProvider(state: fixture.signedIn)
        auth.signOutFailsAfterClearingSession = true
        #expect(await makeViewModel(auth).signOut(force: true) == .signedOut)
        #expect(auth.state == .signedOut)
    }

    @Test func deleteAccountAppleSendsCode() async {
        let auth = FakeAuthProvider(state: .signedIn(userID: fixture.userID, usesApple: true))
        await makeViewModel(auth, usesApple: true).deleteAccount(appleAuthorizationCode: "code-123")
        #expect(auth.lastAppleAuthorizationCode == .some("code-123"))
    }

    @Test func deleteAccountEmailSendsNil() async {
        let auth = FakeAuthProvider(state: fixture.signedIn)
        await makeViewModel(auth).deleteAccount(appleAuthorizationCode: nil)
        #expect(auth.lastAppleAuthorizationCode == .some(nil))
    }

    @Test(.timeLimit(.minutes(1))) func deleteAccountDoubleTapCallsOnce() async {
        let auth = FakeAuthProvider(state: fixture.signedIn)
        let viewModel = makeViewModel(auth)
        await expectSingleCall("deleteAccount", on: auth) { await viewModel.deleteAccount(appleAuthorizationCode: nil) }
    }

    @Test func failedDeleteKeepsDataAndExplains() async {
        fixture.insertProfile()
        let auth = FakeAuthProvider(state: fixture.signedIn)
        auth.nextError["deleteAccount"] = .network
        let viewModel = makeViewModel(auth)
        await viewModel.deleteAccount(appleAuthorizationCode: nil)
        #expect(viewModel.messageKey == "error.network")
        #expect(fixture.context.profile(of: fixture.userID) != nil)
    }
}
