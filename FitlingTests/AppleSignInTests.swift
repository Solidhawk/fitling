import Testing
@testable import Fitling

@Suite struct AppleSignInTests {
    @Test func sha256KnownVector() {
        #expect(AppleSignIn.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func nonceLengthAndCharset() {
        let nonce = AppleSignIn.makeNonce()
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy(allowed.contains))
        #expect(AppleSignIn.makeNonce() != nonce)
    }
}
