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
    /// When true, every call waits until `releaseHeldCalls()`, like a slow network request. Tests use
    /// it to tap a second time while the first request is certainly still in flight.
    var holdsCalls = false
    /// Mimics supabase-swift offline: the session is gone first, then the request throws.
    var signOutFailsAfterClearingSession = false
    private var heldCalls: [CheckedContinuation<Void, Never>] = []

    init(state: AuthState = .signedOut) {
        self.state = state
    }

    func releaseHeldCalls() {
        let held = heldCalls
        heldCalls = []
        held.forEach { $0.resume() }
    }

    private func record(_ name: String) async throws(AuthFailure) {
        calls[name, default: 0] += 1
        if holdsCalls {
            await withCheckedContinuation { heldCalls.append($0) }
        }
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
        do throws(AuthFailure) {
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
        if signOutFailsAfterClearingSession {
            calls["signOut", default: 0] += 1
            state = .signedOut
            throw .network
        }
        try await record("signOut")
        state = .signedOut
    }

    func cancelEmailVerification() {
        if case .awaitingEmailVerification = state { state = .signedOut }
    }
}
#endif
