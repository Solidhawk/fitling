import AuthenticationServices
import Foundation
import Supabase
import Testing
@testable import Fitling

@Suite struct AuthServiceMappingTests {
    func apiError(_ code: ErrorCode, status: Int) -> AuthError {
        .api(
            message: "test",
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }

    @Test func networkErrors() {
        #expect(AuthService.mapAuthError(URLError(.notConnectedToInternet)) == .network)
        #expect(AuthService.mapAuthError(URLError(.timedOut)) == .network)
    }

    @Test func rateLimits() {
        #expect(AuthService.mapAuthError(apiError(.overEmailSendRateLimit, status: 429)) == .rateLimited)
        #expect(AuthService.mapAuthError(apiError(.overRequestRateLimit, status: 429)) == .rateLimited)
        #expect(AuthService.mapAuthError(apiError(.unknown, status: 429)) == .rateLimited)
    }

    @Test func credentialsAndConfirmation() {
        #expect(AuthService.mapAuthError(apiError(.invalidCredentials, status: 400)) == .invalidCredentials)
        #expect(AuthService.mapAuthError(apiError(.emailNotConfirmed, status: 400)) == .emailNotConfirmed)
    }

    @Test func weakPassword() {
        #expect(AuthService.mapAuthError(AuthError.weakPassword(message: "short", reasons: ["length"])) == .weakPassword)
        #expect(AuthService.mapAuthError(apiError(.weakPassword, status: 422)) == .weakPassword)
    }

    @Test func cancelledWebLogin() {
        #expect(AuthService.mapAuthError(ASWebAuthenticationSessionError(.canceledLogin)) == .cancelled)
    }

    @Test func linkFromAnotherDevice() {
        #expect(AuthService.mapAuthError(AuthError.pkceGrantCodeExchange(message: "A code verifier wasn't found in PKCE flow.")) == .invalidOrForeignLink)
    }

    @Test func anExpiredLinkIsToldApartFromALinkFromAnotherDevice() {
        let inQuery = URL(string: "fitling://reset-password?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")!
        let inFragment = URL(string: "fitling://auth-callback#error=access_denied&error_code=otp_expired")!
        #expect(AuthService.failure(inLink: inQuery) == .expiredLink)
        #expect(AuthService.failure(inLink: inFragment) == .expiredLink)
        #expect(AuthService.failure(inLink: URL(string: "fitling://auth-callback?code=abc")!) == nil)
        #expect(AuthService.failure(inLink: URL(string: "fitling://auth-callback?error=server_error")!) == nil)
    }

    @Test func everythingElseIsServer() {
        #expect(AuthService.mapAuthError(FunctionsError.httpError(code: 500, data: Data())) == .server)
        #expect(AuthService.mapAuthError(apiError(.unknown, status: 500)) == .server)
        #expect(AuthService.mapAuthError(NSError(domain: "test", code: 1)) == .server)
    }

    @Test func signedOutWithoutSession() {
        let user = UUID()
        #expect(AuthService.state(userID: nil, providers: [], current: .signedIn(userID: user, usesApple: false)) == .signedOut)
        #expect(AuthService.state(userID: nil, providers: [], current: .loading) == .signedOut)
    }

    @Test func pendingVerificationSurvivesMissingSession() {
        #expect(
            AuthService.state(userID: nil, providers: [], current: .awaitingEmailVerification(email: "a@example.test"))
                == .awaitingEmailVerification(email: "a@example.test")
        )
    }

    @Test func sessionMeansSignedIn() {
        let user = UUID()
        #expect(AuthService.state(userID: user, providers: ["email"], current: .loading) == .signedIn(userID: user, usesApple: false))
        #expect(AuthService.state(userID: user, providers: ["apple"], current: .signedOut) == .signedIn(userID: user, usesApple: true))
    }
}
