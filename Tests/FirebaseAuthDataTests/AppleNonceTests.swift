import Testing
import Foundation
import CryptoKit
@testable import FirebaseAuthData

/// Verifies the nonce generation and SHA-256 hashing used by Sign in with Apple.
/// These helpers guard against replay attacks, so their correctness is
/// security-relevant and worth pinning down with tests.
@MainActor
@Suite("Apple nonce & hashing")
struct AppleNonceTests {

    @Test("Nonce has the requested length")
    func nonceHasRequestedLength() {
        #expect(AppleSignInCoordinator.randomNonce(length: 32).count == 32)
        #expect(AppleSignInCoordinator.randomNonce(length: 8).count == 8)
    }

    @Test("Nonce only contains the allowed Apple charset")
    func nonceUsesAllowedCharset() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = AppleSignInCoordinator.randomNonce(length: 128)
        #expect(nonce.allSatisfy { allowed.contains($0) })
    }

    @Test("Two nonces are practically never equal")
    func noncesAreUnique() {
        let a = AppleSignInCoordinator.randomNonce()
        let b = AppleSignInCoordinator.randomNonce()
        #expect(a != b)
    }

    @Test("SHA-256 is deterministic for the same input")
    func sha256IsDeterministic() {
        let input = "the-quick-brown-fox"
        #expect(AppleSignInCoordinator.sha256Hex(input) == AppleSignInCoordinator.sha256Hex(input))
    }

    @Test("SHA-256 matches CryptoKit's reference output")
    func sha256MatchesReference() {
        let input = "hello"
        let expected = SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(AppleSignInCoordinator.sha256Hex(input) == expected)
    }

    @Test("SHA-256 hex output is 64 characters")
    func sha256ProducesSixtyFourHexChars() {
        let hash = AppleSignInCoordinator.sha256Hex("anything")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }
}
