import AuthenticationServices
import Foundation
import Testing
@testable import Fitling

@MainActor
@Suite struct EmailAuthViewModelTests {
    func makeViewModel(_ mode: EmailAuthViewModel.Mode, auth: FakeAuthProvider) -> EmailAuthViewModel {
        let viewModel = EmailAuthViewModel(auth: auth, mode: mode)
        viewModel.email = " a@example.test "
        viewModel.password = "lang-genoeg"
        return viewModel
    }

    @Test(.timeLimit(.minutes(1))) func signUpCallsAuthOnce() async {
        let auth = FakeAuthProvider()
        let viewModel = makeViewModel(.signUp, auth: auth)
        await expectSingleCall("signUp", on: auth) { await viewModel.submit() }
        #expect(auth.state == .awaitingEmailVerification(email: "a@example.test"))
    }

    @Test func invalidCredentialsShowsMessage() async {
        let auth = FakeAuthProvider()
        auth.nextError["signIn"] = .invalidCredentials
        let viewModel = makeViewModel(.signIn, auth: auth)
        await viewModel.submit()
        #expect(viewModel.messageKey == "auth.error.invalidCredentials")
        #expect(viewModel.isWorking == false)
    }

    @Test func unconfirmedEmailShowsNoErrorBecauseVerificationTakesOver() async {
        let auth = FakeAuthProvider()
        auth.nextError["signIn"] = .emailNotConfirmed
        let viewModel = makeViewModel(.signIn, auth: auth)
        await viewModel.submit()
        #expect(viewModel.messageKey == nil)
        #expect(auth.state == .awaitingEmailVerification(email: "a@example.test"))
    }

    @Test func submitNeedsEmailAndLongEnoughPassword() {
        let viewModel = EmailAuthViewModel(auth: FakeAuthProvider(), mode: .signUp)
        viewModel.email = "geen-adres"
        viewModel.password = "lang-genoeg"
        #expect(viewModel.canSubmit == false)
        viewModel.email = "a@example.test"
        viewModel.password = "kort"
        #expect(viewModel.canSubmit == false)
        viewModel.password = "lang-genoeg"
        #expect(viewModel.canSubmit)
    }
}

@MainActor
@Suite struct WelcomeViewModelTests {
    @Test(.timeLimit(.minutes(1))) func googleCallsAuthOnce() async {
        let auth = FakeAuthProvider()
        let viewModel = WelcomeViewModel(auth: auth)
        await expectSingleCall("signInWithGoogle", on: auth) { await viewModel.signInWithGoogle() }
    }

    @Test func cancelledGoogleShowsNothing() async {
        let auth = FakeAuthProvider()
        auth.nextError["signInWithGoogle"] = .cancelled
        let viewModel = WelcomeViewModel(auth: auth)
        await viewModel.signInWithGoogle()
        #expect(viewModel.messageKey == nil)
    }

    @Test func cancelledAppleShowsNothing() {
        let viewModel = WelcomeViewModel(auth: FakeAuthProvider())
        viewModel.appleFailed(ASAuthorizationError(.canceled))
        #expect(viewModel.messageKey == nil)
        viewModel.appleFailed(ASAuthorizationError(.failed))
        #expect(viewModel.messageKey == "auth.error.apple")
    }

    @Test func appleCredentialSignsIn() async {
        let auth = FakeAuthProvider()
        let viewModel = WelcomeViewModel(auth: auth)
        await viewModel.signInWithApple(AppleSignIn.Credential(idToken: "id", authorizationCode: "code"), nonce: "nonce")
        #expect(auth.calls["signInWithApple"] == 1)
    }
}

@MainActor
@Suite struct ForgotPasswordViewModelTests {
    func makeViewModel(_ auth: FakeAuthProvider) -> ForgotPasswordViewModel {
        let viewModel = ForgotPasswordViewModel(auth: auth)
        viewModel.email = "a@example.test"
        return viewModel
    }

    @Test func neutralMessageOnSuccess() async {
        let viewModel = makeViewModel(FakeAuthProvider())
        await viewModel.submit()
        #expect(viewModel.messageKey == "auth.reset.sent")
    }

    @Test func neutralMessageOnServerError() async {
        let auth = FakeAuthProvider()
        auth.nextError["requestPasswordReset"] = .server
        let viewModel = makeViewModel(auth)
        await viewModel.submit()
        #expect(viewModel.messageKey == "auth.reset.sent")
    }

    @Test func rateLimitAndNetworkAreNamed() async {
        let auth = FakeAuthProvider()
        let viewModel = makeViewModel(auth)
        auth.nextError["requestPasswordReset"] = .rateLimited
        await viewModel.submit()
        #expect(viewModel.messageKey == "auth.reset.rateLimited")
        auth.nextError["requestPasswordReset"] = .network
        await viewModel.submit()
        #expect(viewModel.messageKey == "error.network")
    }

    @Test(.timeLimit(.minutes(1))) func doubleTapSendsOnce() async {
        let auth = FakeAuthProvider()
        let viewModel = makeViewModel(auth)
        await expectSingleCall("requestPasswordReset", on: auth) { await viewModel.submit() }
    }
}

@MainActor
@Suite struct ResetPasswordViewModelTests {
    @Test func linkFromAnotherDeviceIsExplained() async {
        let auth = FakeAuthProvider()
        auth.nextError["updatePassword"] = .invalidOrForeignLink
        let viewModel = ResetPasswordViewModel(auth: auth)
        viewModel.password = "nieuw-wachtwoord"
        await viewModel.submit()
        #expect(viewModel.messageKey == "auth.reset.linkInvalid")
        #expect(viewModel.isDone == false)
    }

    @Test func successFinishes() async {
        let viewModel = ResetPasswordViewModel(auth: FakeAuthProvider())
        viewModel.password = "nieuw-wachtwoord"
        await viewModel.submit()
        #expect(viewModel.isDone)
    }
}

@MainActor
@Suite struct VerifyEmailViewModelTests {
    @Test(.timeLimit(.minutes(1))) func resendOnce() async {
        let auth = FakeAuthProvider(state: .awaitingEmailVerification(email: "a@example.test"))
        let viewModel = VerifyEmailViewModel(auth: auth, email: "a@example.test")
        await expectSingleCall("resendVerification", on: auth) { await viewModel.resend() }
        #expect(viewModel.messageKey == "auth.verify.resent")
    }

    @Test func useOtherAddressGoesBack() {
        let auth = FakeAuthProvider(state: .awaitingEmailVerification(email: "a@example.test"))
        VerifyEmailViewModel(auth: auth, email: "a@example.test").useOtherAddress()
        #expect(auth.state == .signedOut)
    }
}
