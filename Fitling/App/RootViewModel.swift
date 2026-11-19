import Foundation
import Observation

/// Decides which screen the app shows, from the auth state and whether this device has a profile.
@Observable
@MainActor
final class RootViewModel {
    enum Screen: Equatable {
        case loading
        case welcome
        case verifyEmail(String)
        /// Signed in on a device without a profile and the server cannot be reached.
        case needsConnection
        case onboarding(UUID)
        /// Signed in with a profile but no partner yet: after onboarding, or at the first start of
        /// a version that has partners.
        case partnerSetup(UUID)
        case home(UUID)
    }

    private(set) var screen: Screen = .loading
    var showsPasswordReset = false
    private(set) var linkMessageKey: String?
    /// The account an under-18 user is about to delete from onboarding; nil closes the sheet.
    private(set) var underageDeletion: AccountDeletion?
    let auth: any AuthProviding
    let sync: SyncEngine
    let food: FoodServices
    let reminders: any ReminderDelivery
    private var pendingURL: URL?
    /// Goes up with every refresh. A refresh that waited on the network only shows its result
    /// when no newer one started meanwhile; otherwise it could put back a screen that no longer
    /// fits, such as "no connection" after signing out.
    private var generation = 0

    init(auth: any AuthProviding, sync: SyncEngine, food: FoodServices, reminders: any ReminderDelivery) {
        self.auth = auth
        self.sync = sync
        self.food = food
        self.reminders = reminders
    }

    func refresh() async {
        generation += 1
        let current = generation
        if auth.state != .loading, let url = pendingURL {
            pendingURL = nil
            await open(url)
            return
        }
        if case .signedIn = auth.state {} else {
            underageDeletion = nil
        }
        switch auth.state {
        case .loading:
            screen = .loading
        case .signedOut:
            // Health data belongs to the signed-in user only, whatever ended the session. Once on
            // the welcome screen nothing new can be stored, so later refreshes skip the erase.
            if screen != .welcome {
                sync.eraseLocalData()
                // A waiting reminder would still carry the partner's name and mood.
            }
            screen = .welcome
        case let .awaitingEmailVerification(email):
            screen = .verifyEmail(email)
        case let .signedIn(userID, _):
            await route(userID: userID, generation: current)
        }
    }

    private func route(userID: UUID, generation current: Int) async {
        if sync.context.profile(of: userID) != nil {
            if sync.context.profile(of: userID) != nil {
                screen = .home(userID)
                await sync.sync()
                return
            }
            // Another device may have chosen the partner already; ask only once the server says no.
            // Offline the app opens anyway, and the partner tab offers the choice.
            let outcome = await sync.sync()
            guard current == generation else { return }
            if sync.context.creature(of: userID) != nil {
                screen = .home(userID)
            } else if outcome == .completed {
                screen = .partnerSetup(userID)
            } else if screen != .partnerSetup(userID) {
                // Mid-choice the server already confirmed there is no partner; keep the user's choice.
                screen = .home(userID)
            }
            return
        }
        // Never start onboarding before the server has confirmed there is no profile: a new phone
        // or a reinstall would otherwise overwrite the real one.
        let outcome = await sync.sync()
        guard current == generation else { return }
        if outcome == .completed {
            if sync.context.profile(of: userID) == nil {
                screen = .onboarding(userID)
            } else {
                screen = .home(userID)
            }
        } else if screen != .onboarding(userID) {
            // Mid-onboarding the server already confirmed there is no profile; keep the user's answers.
            screen = .needsConnection
        }
    }

    func open(_ url: URL) async {
        guard auth.state != .loading else {
            pendingURL = url
            return
        }
        linkMessageKey = nil
        do throws(AuthFailure) {
            if try await auth.handle(url: url) == .passwordRecovery {
                showsPasswordReset = true
            }
        } catch {
            linkMessageKey = error.messageKey
        }
        await refresh()
    }

    func requestUnderageDeletion(userID: UUID) {
        underageDeletion = AccountDeletion(id: userID)
    }

    func dismissUnderageDeletion() {
        underageDeletion = nil
    }

    func clearLinkMessage() {
        linkMessageKey = nil
    }

    /// The server confirmed there was no profile, so there is no partner either.
    func onboardingFinished(_ profile: UserProfile) async {
        screen = .home(profile.id)
        await sync.sync()
    }

    func partnerChosen(_ creature: Creature) async {
        screen = .home(creature.userID)
        await sync.sync()
    }
}
