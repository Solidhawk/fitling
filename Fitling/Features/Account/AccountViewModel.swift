import Foundation
import Observation

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
    private let sync: ProfileSync
    private let userID: UUID

    init(auth: any AuthProviding, sync: ProfileSync, userID: UUID, usesApple: Bool) {
        self.auth = auth
        self.sync = sync
        self.userID = userID
        self.usesApple = usesApple
    }

    func signOut(force: Bool) async -> SignOutResult {
        guard !isWorking else { return .failed }
        isWorking = true
        messageKey = nil
        defer { isWorking = false }
        if !force {
            try? await sync.push(userID: userID)
            if sync.localProfile(userID: userID)?.needsPush == true {
                return .unsyncedChanges
            }
        }
        do throws(AuthFailure) {
            try await auth.signOut()
        } catch {
            messageKey = error.messageKey
            return .failed
        }
        try? sync.deleteLocalData()
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
            return
        }
        try? sync.deleteLocalData()
    }
}
