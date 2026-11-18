import AuthenticationServices
import Foundation
import Observation

extension AuthFailure {
    /// String Catalog key for the message shown under a form.
    var messageKey: String? {
        switch self {
        case .invalidCredentials: "auth.error.invalidCredentials"
        case .emailNotConfirmed: "auth.error.emailNotConfirmed"
        case .weakPassword: "auth.error.weakPassword"
        case .rateLimited: "auth.error.rateLimited"
        case .network: "error.network"
        case .invalidOrForeignLink: "auth.reset.linkInvalid"
        case .cancelled: nil
        case .server: "error.server"
        }
    }
}

enum Credentials {
    static let minimumPasswordLength = 8

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isPlausibleEmail(_ email: String) -> Bool {
        let parts = normalizedEmail(email).split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}

@Observable
@MainActor
final class WelcomeViewModel {
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding

    init(auth: any AuthProviding) {
        self.auth = auth
    }

    func signInWithGoogle() async {
        guard begin() else { return }
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.signInWithGoogle()
        } catch {
            messageKey = error.messageKey
        }
    }

    func signInWithApple(_ credential: AppleSignIn.Credential, nonce: String) async {
        guard begin() else { return }
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.signInWithApple(idToken: credential.idToken, nonce: nonce)
        } catch {
            messageKey = error.messageKey
        }
    }

    func appleFailed(_ error: any Error) {
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            messageKey = nil
        } else {
            messageKey = "auth.error.apple"
        }
    }

    /// Claims the screen for one request; a second tap while it runs is ignored.
    private func begin() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        messageKey = nil
        return true
    }
}

@Observable
@MainActor
final class EmailAuthViewModel {
    enum Mode: Equatable {
        case signUp, signIn
    }

    var mode: Mode
    var email = ""
    var password = ""
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding

    init(auth: any AuthProviding, mode: Mode) {
        self.auth = auth
        self.mode = mode
    }

    var canSubmit: Bool {
        !isWorking && Credentials.isPlausibleEmail(email) && password.count >= Credentials.minimumPasswordLength
    }

    func submit() async {
        guard !isWorking else { return }
        isWorking = true
        messageKey = nil
        defer { isWorking = false }
        let email = Credentials.normalizedEmail(email)
        do throws(AuthFailure) {
            switch mode {
            case .signUp: try await auth.signUp(email: email, password: password)
            case .signIn: try await auth.signIn(email: email, password: password)
            }
        } catch .emailNotConfirmed {
            // The auth state has moved to "confirm your email"; that screen explains it.
        } catch {
            messageKey = error.messageKey
        }
    }
}

@Observable
@MainActor
final class ForgotPasswordViewModel {
    var email = ""
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding

    init(auth: any AuthProviding) {
        self.auth = auth
    }

    var canSubmit: Bool { !isWorking && Credentials.isPlausibleEmail(email) }

    func submit() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.requestPasswordReset(email: Credentials.normalizedEmail(email))
            messageKey = "auth.reset.sent"
        } catch .rateLimited {
            messageKey = "auth.reset.rateLimited"
        } catch .network {
            messageKey = "error.network"
        } catch {
            // Same answer whether or not the address has an account, so nobody can probe for one.
            messageKey = "auth.reset.sent"
        }
    }
}

@Observable
@MainActor
final class ResetPasswordViewModel {
    var password = ""
    private(set) var isWorking = false
    private(set) var isDone = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding

    init(auth: any AuthProviding) {
        self.auth = auth
    }

    var canSubmit: Bool { !isWorking && password.count >= Credentials.minimumPasswordLength }

    func submit() async {
        guard !isWorking else { return }
        isWorking = true
        messageKey = nil
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.updatePassword(password)
            isDone = true
        } catch {
            messageKey = error.messageKey
        }
    }
}

@Observable
@MainActor
final class VerifyEmailViewModel {
    let email: String
    private(set) var isWorking = false
    private(set) var messageKey: String?
    private let auth: any AuthProviding

    init(auth: any AuthProviding, email: String) {
        self.auth = auth
        self.email = email
    }

    func resend() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do throws(AuthFailure) {
            try await auth.resendVerification(email: email)
            messageKey = "auth.verify.resent"
        } catch {
            messageKey = error.messageKey
        }
    }

    func useOtherAddress() {
        auth.cancelEmailVerification()
    }
}
