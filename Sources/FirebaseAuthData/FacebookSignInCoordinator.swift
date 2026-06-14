import UIKit
import CryptoKit
import FacebookLogin
import FirebaseAuth
import AuthDomain

/// Drives a native Facebook **Limited Login** flow and returns the data
/// Firebase needs to mint an OIDC credential: the authentication (OIDC) token
/// and the raw nonce.
///
/// Limited Login is required because, under Apple's App Tracking Transparency,
/// classic Facebook Login no longer returns a usable OAuth access token when
/// the user hasn't granted tracking consent (the SDK redirects to
/// `limited.facebook.com` and `result.token` comes back nil). Limited Login
/// instead returns a signed OIDC `AuthenticationToken`, which Firebase accepts
/// via `OAuthProvider.credential(providerID: "facebook.com", idToken:rawNonce:)`.
@MainActor
final class FacebookSignInCoordinator {

    struct Result {
        let credential: AuthCredential
        let displayName: String?
        let email: String?
    }

    func signIn() async throws -> Result {
        // A fresh nonce per request. Facebook receives the SHA256 hash; Firebase
        // receives the raw value to verify the returned token was minted for us.
        let rawNonce = Self.randomNonce()
        let hashedNonce = Self.sha256(rawNonce)

        guard let configuration = LoginConfiguration(
            permissions: ["public_profile", "email"],
            tracking: .limited,
            nonce: hashedNonce
        ) else {
            throw AuthServiceError.message("Failed to build Facebook login configuration.")
        }

        let manager = LoginManager()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.logIn(configuration: configuration) { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .cancelled:
                    continuation.resume(throwing: AuthServiceError.message(AuthCancellation.sentinel))
                case let .failed(error):
                    continuation.resume(throwing: error)
                }
            }
        }

        // Limited Login returns an OIDC AuthenticationToken (NOT an access token).
        guard let idTokenString = AuthenticationToken.current?.tokenString else {
            throw AuthServiceError.message("Facebook login did not return an authentication token.")
        }

        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.facebook,
            idToken: idTokenString,
            rawNonce: rawNonce
        )

        // Profile is populated by Limited Login for the granted fields.
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

    // MARK: - Nonce

    /// A cryptographically secure random string used to protect against replay.
    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
