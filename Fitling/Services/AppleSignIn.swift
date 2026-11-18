import AuthenticationServices
import CryptoKit
import Foundation

enum AppleSignIn {
    private static let nonceCharacters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    /// The raw nonce goes to Supabase; Apple only ever sees its SHA-256 hash.
    static func makeNonce(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in nonceCharacters.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    struct Credential: Sendable {
        let idToken: String
        let authorizationCode: String
    }

    /// Extracts the tokens from a completed `SignInWithAppleButton` request.
    static func credential(from authorization: ASAuthorization) -> Credential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken, let idToken = String(data: tokenData, encoding: .utf8),
              let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8)
        else { return nil }
        return Credential(idToken: idToken, authorizationCode: code)
    }
}
