#if DEBUG
import Foundation
import Observation

/// Stand-in for `AuthService` in unit tests and the UI test; never compiled into a release build.
@Observable
@MainActor
final class FakeAuthProvider: AuthProviding {
    var state: AuthState
    /// The error the next call to a method (by name, e.g. "signUp") throws.
    var nextError: [String: AuthFailure] = [:]
    var nextLink: AuthLink = .signedIn
    private(set) var calls: [String: Int] = [:]
    private(set) var lastAppleAuthorizationCode: String??

    init(state: AuthState = .signedOut) {
        self.state = state
    }

    private func record(_ name: String) async throws(AuthFailure) {
        calls[name, default: 0] += 1
        // Lets a second tap run while this call is still in flight, as a network call would.
        await Task.yield()
        if let error = nextError.removeValue(forKey: name) { throw error }
    }

    func signInWithApple(idToken: String, nonce: String) async throws(AuthFailure) {
        try await record("signInWithApple")
        state = .signedIn(userID: UUID(), usesApple: true)
    }

    func signInWithGoogle() async throws(AuthFailure) {
        try await record("signInWithGoogle")
        state = .signedIn(userID: UUID(), usesApple: false)
    }

    func signUp(email: String, password: String) async throws(AuthFailure) {
        try await record("signUp")
        state = .awaitingEmailVerification(email: email)
    }

    func signIn(email: String, password: String) async throws(AuthFailure) {
        do {
            try await record("signIn")
        } catch .emailNotConfirmed {
            state = .awaitingEmailVerification(email: email)
            throw .emailNotConfirmed
        }
        state = .signedIn(userID: UUID(), usesApple: false)
    }

    func resendVerification(email: String) async throws(AuthFailure) {
        try await record("resendVerification")
    }

    func requestPasswordReset(email: String) async throws(AuthFailure) {
        try await record("requestPasswordReset")
    }

    func handle(url: URL) async throws(AuthFailure) -> AuthLink {
        try await record("handle")
        return nextLink
    }

    func updatePassword(_ password: String) async throws(AuthFailure) {
        try await record("updatePassword")
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws(AuthFailure) {
        lastAppleAuthorizationCode = .some(appleAuthorizationCode)
        try await record("deleteAccount")
        state = .signedOut
    }

    func signOut() async throws(AuthFailure) {
        try await record("signOut")
        state = .signedOut
    }
}
#endif
