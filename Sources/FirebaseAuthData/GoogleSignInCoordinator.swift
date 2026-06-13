import UIKit
import GoogleSignIn
import FirebaseAuth
import AuthDomain

/// Drives a native Google Sign-In flow and returns a Firebase credential.
///
/// The coordinator wraps `GIDSignIn.sharedInstance.signIn(withPresenting:)` in
/// a clean async/await interface. The caller exchanges the returned credential
/// directly with `Auth.auth().signIn(with:)`.
@MainActor
final class GoogleSignInCoordinator {

    struct Result {
        let credential: AuthCredential
        let displayName: String?
        let email: String?
    }

    /// Presents the Google sign-in sheet and resolves with a Firebase credential.
    func signIn() async throws -> Result {
        guard let rootViewController = Self.rootViewController() else {
            throw AuthServiceError.message("Unable to find a root view controller for Google Sign-In.")
        }

        let gidResult: GIDSignInResult
        do {
            gidResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        } catch {
            if (error as? GIDSignInError)?.code == .canceled {
                throw AuthServiceError.message(AuthCancellation.sentinel)
            }
            throw error
        }
        let user = gidResult.user

        guard let idToken = user.idToken?.tokenString else {
            throw AuthServiceError.message("Google Sign-In did not return an ID token.")
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: user.accessToken.tokenString
        )

        let displayName = user.profile?.name
        let email = user.profile?.email
        return Result(credential: credential, displayName: displayName, email: email)
    }

    // MARK: - Helpers

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
