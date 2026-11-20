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
    let health: any HealthReading
    let shopping: ShoppingServices
    private var pendingURL: URL?
    /// Goes up with every refresh. A refresh that waited on the network only shows its result
    /// when no newer one started meanwhile; otherwise it could put back a screen that no longer
    /// fits, such as "no connection" after signing out.
    private var generation = 0

    init(
        auth: any AuthProviding, sync: SyncEngine, food: FoodServices, reminders: any ReminderDelivery, health: any HealthReading,
        shopping: ShoppingServices
    ) {
        self.auth = auth
        self.sync = sync
        self.food = food
        self.reminders = reminders
        self.health = health
        self.shopping = shopping
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
            // Signing out or deleting the account on purpose erases everything on this device. A
            // session that ends by itself (a refresh token that expired after a long time offline)
            // must not take changes the server has not seen with it: they stay on this device,
            // behind the welcome screen, until the same user signs in and they are sent; another
            // user signing in erases them first (UNFORGET S12). Once on the welcome screen nothing
            // new can be stored, so later refreshes skip this.
            if screen != .welcome {
                if auth.signedOutOnRequest || !sync.hasUnsentChanges || sync.context.localOwner() == nil {
                    eraseLocalData()
                }
                // A waiting reminder would still carry the partner's name and mood.
                reminders.replace(with: [], title: "")
            }
            screen = .welcome
        case let .awaitingEmailVerification(email):
            screen = .verifyEmail(email)
        case let .signedIn(userID, _):
            // Changes kept from a session that ended by itself belong to that user only.
            if let owner = sync.context.localOwner(), owner != userID {
                eraseLocalData()
            }
            await route(userID: userID, generation: current)
        }
    }

    /// Health data belongs to the signed-in user only: the synced tables and the progress photos,
    /// which live on this device alone.
    private func eraseLocalData() {
        sync.eraseLocalData()
        ProgressPhotoStore(context: sync.context).removeAll()
    }

    private func route(userID: UUID, generation current: Int) async {
        if sync.context.profile(of: userID) != nil {
            if sync.context.creature(of: userID) != nil {
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
                screen = sync.context.creature(of: userID) == nil ? .partnerSetup(userID) : .home(userID)
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
        screen = .partnerSetup(profile.id)
        await sync.sync()
    }

    func partnerChosen(_ creature: Creature) async {
        screen = .home(creature.userID)
        await sync.sync()
    }
}
