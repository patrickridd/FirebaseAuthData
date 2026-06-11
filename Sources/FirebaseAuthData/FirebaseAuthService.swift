import Foundation
import AuthDomain
import FirebaseAuth

/// A Firebase-backed implementation of `AuthService`.
///
/// This is the *data* layer: it adapts Firebase's `FirebaseAuth` SDK to the
/// backend-agnostic `AuthService` contract from `AuthDomain`. The UI layer
/// (`FeatureAuth`) depends only on the contract and never imports Firebase.
///
/// ```swift
/// import FirebaseCore
/// import FirebaseAuthData
///
/// FirebaseApp.configure()             // once, at app launch
/// let service = FirebaseAuthService() // inject into AuthFlowView
/// ```
///
/// - Important: Make sure `FirebaseApp.configure()` has run (and your
///   `GoogleService-Info.plist` is present) before using this service.
public final class FirebaseAuthService: AuthService {

    public init() {}

    // MARK: - Email + password

    public func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return Self.mapUser(result.user)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    public func signUp(firstName: String, lastName: String,
                       email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let displayName = Self.displayName(firstName: firstName, lastName: lastName)
            if !displayName.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = displayName
                try await change.commitChanges()
            }
            return Self.mapUser(result.user, fallbackName: displayName)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Social

    /// Social sign-in requires provider SDKs (Sign in with Apple, GoogleSignIn)
    /// to produce an `AuthCredential`. Wire those in a follow-up; for now we
    /// surface a clear `notImplemented` error per provider.
    public func signIn(with provider: SocialAuthProvider) async throws -> AuthUser {
        throw AuthServiceError.notImplemented("Sign in with \(provider.rawValue.capitalized)")
    }

    // MARK: - Password reset

    public func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Mapping

    private static func mapUser(_ user: User, fallbackName: String? = nil) -> AuthUser {
        let name = user.displayName?.nonEmpty ?? fallbackName?.nonEmpty
        return AuthUser(id: user.uid, email: user.email, displayName: name)
    }

    private static func displayName(firstName: String, lastName: String) -> String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
