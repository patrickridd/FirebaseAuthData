import Testing
import Foundation
import FirebaseAuth
import AuthDomain
@testable import FirebaseAuthData

/// Exercises `AuthServiceError.from(_:)`, the seam that translates raw Firebase
/// `NSError`s into friendly, UI-ready messages. This is pure mapping logic with
/// no network or Firebase-app dependency, so it is a perfect unit-test target.
@Suite("AuthServiceError mapping")
struct AuthServiceErrorMappingTests {

    /// Builds an `NSError` in Firebase's auth domain for a given code, mirroring
    /// what FirebaseAuth hands back at runtime.
    private func firebaseError(_ code: AuthErrorCode) -> NSError {
        NSError(domain: AuthErrorDomain, code: code.rawValue, userInfo: nil)
    }

    @Test("An existing AuthServiceError passes through unchanged")
    func passesThroughExistingError() {
        let original = AuthServiceError.message("already friendly")
        let mapped = AuthServiceError.from(original)
        #expect(mapped.errorDescription == "already friendly")
    }

    @Test("A non-Firebase error falls back to its localized description")
    func fallsBackForUnknownDomain() {
        let error = NSError(
            domain: "com.example.other",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "something broke"]
        )
        let mapped = AuthServiceError.from(error)
        #expect(mapped.errorDescription == "something broke")
    }

    @Test("Invalid email maps to a friendly message")
    func mapsInvalidEmail() {
        let mapped = AuthServiceError.from(firebaseError(.invalidEmail))
        #expect(mapped.errorDescription == "That email address doesn't look right.")
    }

    @Test("Email already in use maps to a friendly message")
    func mapsEmailAlreadyInUse() {
        let mapped = AuthServiceError.from(firebaseError(.emailAlreadyInUse))
        #expect(mapped.errorDescription == "An account already exists with this email.")
    }

    @Test("Weak password maps to a friendly message")
    func mapsWeakPassword() {
        let mapped = AuthServiceError.from(firebaseError(.weakPassword))
        #expect(mapped.errorDescription == "Please choose a stronger password (at least 6 characters).")
    }

    @Test("Wrong password and invalid credential share the same message")
    func mapsWrongPasswordAndInvalidCredential() {
        let wrong = AuthServiceError.from(firebaseError(.wrongPassword))
        let invalid = AuthServiceError.from(firebaseError(.invalidCredential))
        #expect(wrong.errorDescription == "Incorrect email or password.")
        #expect(invalid.errorDescription == "Incorrect email or password.")
    }

    @Test("User not found maps to a friendly message")
    func mapsUserNotFound() {
        let mapped = AuthServiceError.from(firebaseError(.userNotFound))
        #expect(mapped.errorDescription == "No account found with this email.")
    }

    @Test("Disabled account maps to a friendly message")
    func mapsUserDisabled() {
        let mapped = AuthServiceError.from(firebaseError(.userDisabled))
        #expect(mapped.errorDescription == "This account has been disabled.")
    }

    @Test("Too many requests maps to a friendly message")
    func mapsTooManyRequests() {
        let mapped = AuthServiceError.from(firebaseError(.tooManyRequests))
        #expect(mapped.errorDescription == "Too many attempts. Please try again later.")
    }

    @Test("Network error maps to a friendly message")
    func mapsNetworkError() {
        let mapped = AuthServiceError.from(firebaseError(.networkError))
        #expect(mapped.errorDescription == "Network error. Check your connection and try again.")
    }

    @Test("An unhandled Firebase code falls back to its localized description")
    func mapsUnhandledCodeToLocalizedDescription() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.keychainError.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "keychain trouble"]
        )
        let mapped = AuthServiceError.from(error)
        #expect(mapped.errorDescription == "keychain trouble")
    }
}
