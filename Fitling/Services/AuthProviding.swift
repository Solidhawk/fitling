import Foundation

enum AuthState: Equatable, Sendable {
    case loading
    case signedOut
    case awaitingEmailVerification(email: String)
    case signedIn(userID: UUID, usesApple: Bool)
}

/// What an opened `fitling://` link turned out to be.
enum AuthLink: Equatable, Sendable {
    case signedIn
    case passwordRecovery
}

enum AuthFailure: Error, Equatable, Sendable {
    case invalidCredentials
    case emailNotConfirmed
    case weakPassword
    case rateLimited
    case network
    /// A reset or confirmation link opened on another device or after a reinstall.
    case invalidOrForeignLink
    /// A reset or confirmation link that is too old or was already used.
    case expiredLink
    /// The user closed the Apple or Google sheet; not an error worth showing.
    case cancelled
    case server
}

@MainActor
protocol AuthProviding: AnyObject {
    var state: AuthState { get }
    func signInWithApple(idToken: String, nonce: String) async throws(AuthFailure)
    func signInWithGoogle() async throws(AuthFailure)
    func signUp(email: String, password: String) async throws(AuthFailure)
    func signIn(email: String, password: String) async throws(AuthFailure)
    func resendVerification(email: String) async throws(AuthFailure)
    func requestPasswordReset(email: String) async throws(AuthFailure)
    func handle(url: URL) async throws(AuthFailure) -> AuthLink
    func updatePassword(_ password: String) async throws(AuthFailure)
    func deleteAccount(appleAuthorizationCode: String?) async throws(AuthFailure)
    func signOut() async throws(AuthFailure)
    /// Leaves the "confirm your email" screen, for example after a typo in the address.
    func cancelEmailVerification()
}
