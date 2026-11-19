import Foundation
import Observation

/// Signing out and deleting the account. Wiping the local data is left to `RootViewModel`, which
/// does it in the same step as showing the welcome screen; doing it here first left a moment in
/// which the profile screen had no profile.
@Observable
@MainActor
final class AccountViewModel {
    enum SignOutResult: Equatable {
        case signedOut
        /// Offline with edits the server has not seen; signing out now would lose them.
        case unsyncedChanges
        case failed
    }

    let usesApple: Bool
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding
    private let sync: SyncEngine

    init(auth: any AuthProviding, sync: SyncEngine, usesApple: Bool) {
        self.auth = auth
        self.sync = sync
        self.usesApple = usesApple
    }

    func signOut(force: Bool) async -> SignOutResult {
        guard !isWorking else { return .failed }
        isWorking = true
        messageKey = nil
        defer { isWorking = false }
        if !force {
            await sync.sync()
            if sync.hasUnsentChanges {
                return .unsyncedChanges
            }
        }
        do throws(AuthFailure) {
            try await auth.signOut()
        } catch {
            // Only a sign-out that left the session in place is a failure.
            if auth.state != .signedOut {
                messageKey = error.messageKey
                return .failed
            }
        }
        sync.eraseLocalData()
        return .signedOut
    }

    func deleteAccount(appleAuthorizationCode: String?) async {
        guard !isWorking else { return }
        isWorking = true
        messageKey = nil
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        } catch {
            messageKey = error.messageKey
        }
    }
}
