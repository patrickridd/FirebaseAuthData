import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import AuthDomain

/// Drives a native Sign in with Apple request and returns the data Firebase
/// needs to mint a credential: the identity token, the raw nonce, and the
/// (first-time-only) full name.
///
/// Apple only returns the user's name on the *very first* authorization, so we
/// surface it here for the caller to persist as a Firebase display name.
@MainActor
final class AppleSignInCoordinator: NSObject {

    struct Result {
        let idToken: String
        let rawNonce: String
        let fullName: PersonNameComponents?
        let email: String?
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var currentNonce: String?

    /// Presents the Apple sheet and resolves with the token + nonce.
    func signIn() async throws -> Result {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Nonce

    /// A cryptographically secure random string used to protect against replay.
    static func randomNonce(length: Int = 32) -> String {
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

#if DEBUG
extension AppleSignInCoordinator {
    /// Test-only exposure of the SHA-256 helper.
    static func sha256Hex(_ input: String) -> String { sha256(input) }
}
#endif

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { continuation = nil }
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            continuation?.resume(throwing:
                AuthServiceError.message("Apple sign-in returned no identity token."))
            return
        }
        continuation?.resume(returning: Result(
            idToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName,
            email: credential.email
        ))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        defer { continuation = nil }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthServiceError.message(AuthCancellation.sentinel))
        } else {
            continuation?.resume(throwing: AuthServiceError.from(error))
        }
    }
}

// MARK: - Presentation anchor

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
