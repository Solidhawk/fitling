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
        case home(UUID)
    }

    private(set) var screen: Screen = .loading
    var showsPasswordReset = false
    private(set) var linkMessageKey: String?
    /// The account an under-18 user is deleting from onboarding; nil closes the sheet.
    private(set) var underageDeletion: AccountDeletion?
    let auth: any AuthProviding
    let sync: ProfileSync
    private var pendingURL: URL?

    init(auth: any AuthProviding, sync: ProfileSync) {
        self.auth = auth
        self.sync = sync
    }

    func refresh() async {
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
            // Health data belongs to the signed-in user only, whatever ended the session.
            try? sync.deleteLocalData()
            screen = .welcome
        case let .awaitingEmailVerification(email):
            screen = .verifyEmail(email)
        case let .signedIn(userID, _):
            await route(userID: userID)
        }
    }

    private func route(userID: UUID) async {
        if sync.localProfile(userID: userID) != nil {
            screen = .home(userID)
            try? await sync.push(userID: userID)
            _ = try? await sync.pull(userID: userID)
            return
        }
        // Never start onboarding before the server has confirmed there is no profile: a new phone
        // or a reinstall would otherwise overwrite the real one.
        do throws(SyncError) {
            let outcome = try await sync.pull(userID: userID)
            screen = outcome == .remoteMissing ? .onboarding(userID) : .home(userID)
        } catch {
            // Mid-onboarding the server already confirmed there is no profile; keep the user's answers.
            if screen != .onboarding(userID) { screen = .needsConnection }
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

    func onboardingFinished(_ profile: UserProfile) async {
        screen = .home(profile.id)
        try? await sync.push(userID: profile.id)
    }
}
