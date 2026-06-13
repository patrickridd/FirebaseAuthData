import UIKit
import FacebookLogin
import FirebaseAuth
import AuthDomain

/// Drives a native Facebook Login flow and returns a Firebase credential.
@MainActor
final class FacebookSignInCoordinator {

    struct Result {
        let credential: AuthCredential
        let displayName: String?
        let email: String?
    }

    func signIn() async throws -> Result {
        let manager = LoginManager()

        let fbResult: LoginManagerLoginResult = try await withCheckedThrowingContinuation { continuation in
            manager.logIn(permissions: ["public_profile", "email"], from: nil) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, !result.isCancelled else {
                    continuation.resume(throwing: AuthServiceError.message(AuthCancellation.sentinel))
                    return
                }
                continuation.resume(returning: result)
            }
        }

        guard let tokenString = fbResult.token?.tokenString else {
            throw AuthServiceError.message("Facebook login did not return an access token.")
        }

        let credential = FacebookAuthProvider.credential(withAccessToken: tokenString)

        let profile = Profile.current
        let displayName = profile.flatMap {
            [$0.firstName, $0.lastName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .nonEmpty
        }

        return Result(credential: credential, displayName: displayName, email: profile?.email)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
