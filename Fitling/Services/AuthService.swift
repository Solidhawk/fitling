import AuthenticationServices
import Foundation
import Observation
import Supabase

func makeSupabaseClient(_ config: AppConfiguration) -> SupabaseClient {
    SupabaseClient(
        supabaseURL: config.supabaseURL,
        supabaseKey: config.publishableKey,
        options: SupabaseClientOptions(
            // A stored session counts at a cold start, also offline; an expired access token is
            // refreshed in the background instead of signing the user out.
            auth: .init(redirectToURL: AuthService.authCallbackURL, emitLocalSessionAsInitialSession: true)
        )
    )
}

@Observable
@MainActor
final class AuthService: AuthProviding {
    nonisolated static let authCallbackURL = URL(string: "fitling://auth-callback")!
    nonisolated static let resetPasswordURL = URL(string: "fitling://reset-password")!

    private(set) var state: AuthState = .loading
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
        Task { [weak self] in
            for await (_, session) in client.auth.authStateChanges {
                guard let self else { return }
                let providers = session?.user.identities?.map(\.provider) ?? []
                self.state = Self.state(userID: session?.user.id, providers: providers, current: self.state)
            }
        }
    }

    nonisolated static func state(userID: UUID?, providers: [String], current: AuthState) -> AuthState {
        guard let userID else {
            if case .awaitingEmailVerification = current { return current }
            return .signedOut
        }
        return .signedIn(userID: userID, usesApple: providers.contains("apple"))
    }

    nonisolated static func mapAuthError(_ error: any Error) -> AuthFailure {
        if error is URLError { return .network }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return .cancelled }
        guard let error = error as? AuthError else { return .server }
        switch error {
        case .weakPassword:
            return .weakPassword
        case .pkceGrantCodeExchange:
            return .invalidOrForeignLink
        case let .api(_, code, _, response):
            if response.statusCode == 429 || code == .overRequestRateLimit || code == .overEmailSendRateLimit {
                return .rateLimited
            }
            switch code {
            case .invalidCredentials: return .invalidCredentials
            case .emailNotConfirmed: return .emailNotConfirmed
            case .weakPassword: return .weakPassword
            default: return .server
            }
        default:
            return .server
        }
    }

    /// What a link says went wrong, read from the link itself. The library reports every failed
    /// link as a PKCE error, which would tell the user to open it on the device that asked for it;
    /// for an expired link that advice is wrong.
    nonisolated static func failure(inLink url: URL) -> AuthFailure? {
        // Supabase reports it in the query (PKCE) or in the fragment (implicit flow).
        let parts = [url.query(percentEncoded: true), url.fragment(percentEncoded: true)].compactMap { $0 }
        let isExpired = parts.contains { $0.split(separator: "&").contains("error_code=otp_expired") }
        return isExpired ? .expiredLink : nil
    }

    private func perform<T: Sendable>(_ operation: () async throws -> T) async throws(AuthFailure) -> T {
        do {
            return try await operation()
        } catch {
            throw Self.mapAuthError(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws(AuthFailure) {
        _ = try await perform {
            try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        }
    }

    func signInWithGoogle() async throws(AuthFailure) {
        _ = try await perform {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.authCallbackURL)
        }
    }

    func signUp(email: String, password: String) async throws(AuthFailure) {
        let response = try await perform {
            try await client.auth.signUp(email: email, password: password, redirectTo: Self.authCallbackURL)
        }
        if response.session == nil {
            state = .awaitingEmailVerification(email: email)
        }
    }

    func signIn(email: String, password: String) async throws(AuthFailure) {
        do throws(AuthFailure) {
            _ = try await perform { try await client.auth.signIn(email: email, password: password) }
        } catch .emailNotConfirmed {
            state = .awaitingEmailVerification(email: email)
            throw .emailNotConfirmed
        }
    }

    func resendVerification(email: String) async throws(AuthFailure) {
        try await perform {
            try await client.auth.resend(email: email, type: .signup, emailRedirectTo: Self.authCallbackURL)
        }
    }

    func requestPasswordReset(email: String) async throws(AuthFailure) {
        try await perform {
            try await client.auth.resetPasswordForEmail(email, redirectTo: Self.resetPasswordURL)
        }
    }

    func handle(url: URL) async throws(AuthFailure) -> AuthLink {
        if let failure = Self.failure(inLink: url) { throw failure }
        _ = try await perform { try await client.auth.session(from: url) }
        return url.host == Self.resetPasswordURL.host ? .passwordRecovery : .signedIn
    }

    func updatePassword(_ password: String) async throws(AuthFailure) {
        _ = try await perform { try await client.auth.update(user: UserAttributes(password: password)) }
    }

    private struct DeleteAccountBody: Encodable {
        let appleAuthorizationCode: String?
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws(AuthFailure) {
        try await perform {
            try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode))
            )
        }
        // The server session no longer exists; only the local one is left to clear.
        try? await client.auth.signOut(scope: .local)
        state = .signedOut
    }

    func signOut() async throws(AuthFailure) {
        do throws(AuthFailure) {
            try await perform { try await client.auth.signOut(scope: .local) }
        } catch .network {
            // The library removed the local session before the request failed; the user is signed out.
        }
        state = .signedOut
    }

    func cancelEmailVerification() {
        if case .awaitingEmailVerification = state { state = .signedOut }
    }
}
