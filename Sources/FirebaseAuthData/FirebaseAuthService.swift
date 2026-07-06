import Foundation
import AuthDomain
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import FacebookLogin
import os

public extension Notification.Name {
    /// Posted after the signed-in user's profile (e.g. display name) is
    /// updated. Firebase's auth-state listener does *not* fire for profile
    /// changes, so this package posts an explicit notification to let observers
    /// refresh derived UI such as the dashboard hero header and toolbar avatar.
    /// The `object` is the updated ``AuthUser`` when available.
    static let authUserProfileDidChange = Notification.Name("FirebaseAuthData.authUserProfileDidChange")
}

/// Package-local Unified Logging channel for FirebaseAuthData.
///
/// This package depends on `AuthDomain` (a standalone, independently-versioned
/// package), not on the app's `Domain`, so it deliberately does not reach for
/// `Domain.AppLogger`. Routing through `os.Logger` keeps the package
/// self-contained while still landing in Console.app with structured levels,
/// category filtering, and privacy redaction.
private let authLog = Logger(subsystem: "FeatureAuth-Dev.FirebaseAuthData", category: "Auth")

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

    /// Call once at app launch instead of importing `FirebaseCore` in the host app.
    /// Safe to call multiple times — no-ops after first configuration.
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        guard let plistURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            authLog.error("🔐 ❌ GoogleService-Info.plist not found — Firebase not configured.")
            return
        }

        FirebaseApp.configure()

        // Configure Google Sign-In with the client ID from the plist.
        // GIDSignIn requires this to be set explicitly when the plist is not
        // the app's own Info.plist (i.e. when loaded as a bundle resource).
        if let plistDict = NSDictionary(contentsOf: plistURL),
           let clientID = plistDict["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        } else {
            authLog.error("🔐 ❌ CLIENT_ID missing from GoogleService-Info.plist — Google Sign-In won't work.")
        }

        // Facebook SDK is initialised lazily on first use — NOT at launch.
        // This avoids the SDK's bundle-ID network validation running at startup
        // which can crash the app before any UI appears.
    }

    // MARK: - Facebook lazy init

    @MainActor private static var facebookSDKReady = false

    /// Initialises the Facebook SDK on first call only, deferred until the
    /// user actually attempts a Facebook sign-in. Safe to call multiple times.
    @MainActor
    static func ensureFacebookSDKReady() throws {
        guard !facebookSDKReady else { return }
        let fbAppID = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String ?? ""
        let fbToken = Bundle.main.object(forInfoDictionaryKey: "FacebookClientToken") as? String ?? ""
        authLog.debug("🔐 💬 FB lazy init bundleID='\(Bundle.main.bundleIdentifier ?? "?", privacy: .public)' appID='\(fbAppID, privacy: .public)' tokenLen=\(fbToken.count, privacy: .public)")
        guard !fbAppID.isEmpty, !fbToken.isEmpty else {
            throw AuthServiceError.message("Facebook Sign-In is not configured (missing plist keys).")
        }
        ApplicationDelegate.shared.application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: nil
        )
        facebookSDKReady = true
        authLog.info("🔐 ℹ️ Facebook SDK ready.")
    }

    /// No-op at launch — Facebook SDK is initialised lazily on first sign-in.
    /// Kept for AppDelegate API compatibility.
    @MainActor
    public static func configureFacebook(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) {
        authLog.debug("🔐 💬 Facebook init deferred to first sign-in attempt.")
    }

    /// Forward URL callbacks (Facebook OAuth redirect).
    @MainActor
    public static func handleOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard facebookSDKReady else { return false }
        return ApplicationDelegate.shared.application(
            UIApplication.shared,
            open: url,
            sourceApplication: options[.sourceApplication] as? String,
            annotation: options[.annotation] ?? ""
        )
    }

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

    /// Social sign-in. `.apple` is fully wired via `AuthenticationServices`;
    /// `.google` / `.facebook` require their respective SDKs and surface a
    /// clear `notImplemented` error until those are added.
    public func signIn(with provider: SocialAuthProvider) async throws -> AuthUser {
        switch provider {
        case .apple:
            return try await signInWithApple()
        case .google:
            return try await signInWithGoogle()
        case .facebook:
            return try await signInWithFacebook()
        }
    }

    // MARK: - Facebook

    // MARK: - Facebook

    @MainActor
    private func signInWithFacebook() async throws -> AuthUser {
        do {
            try Self.ensureFacebookSDKReady()
            let coordinator = FacebookSignInCoordinator()
            let fb = try await coordinator.signIn()
            let result = try await Auth.auth().signIn(with: fb.credential)
            if result.user.displayName?.nonEmpty == nil, let name = fb.displayName {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try await change.commitChanges()
            }
            return Self.mapUser(result.user, fallbackName: fb.displayName)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Apple

    @MainActor
    private func signInWithApple() async throws -> AuthUser {
        do {
            let coordinator = AppleSignInCoordinator()
            let apple = try await coordinator.signIn()

            let credential = OAuthProvider.appleCredential(
                withIDToken: apple.idToken,
                rawNonce: apple.rawNonce,
                fullName: apple.fullName
            )

            let result = try await Auth.auth().signIn(with: credential)

            // Apple only returns the full name on first authorization. If the
            // Firebase profile has no display name yet, persist it now.
            let appleName = Self.formattedName(apple.fullName)
            if result.user.displayName?.nonEmpty == nil, let appleName {
                let change = result.user.createProfileChangeRequest()
                change.displayName = appleName
                try await change.commitChanges()
            }
            return Self.mapUser(result.user, fallbackName: appleName)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Google

    @MainActor
    private func signInWithGoogle() async throws -> AuthUser {
        do {
            let coordinator = GoogleSignInCoordinator()
            let google = try await coordinator.signIn()
            let result = try await Auth.auth().signIn(with: google.credential)

            // Persist the Google display name if Firebase profile is still empty.
            if result.user.displayName?.nonEmpty == nil, let name = google.displayName {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try await change.commitChanges()
            }
            return Self.mapUser(result.user, fallbackName: google.displayName)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Password reset

    public func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Sign out

    /// Clears every session the app holds: Firebase, Google, and Facebook.
    ///
    /// Firebase sign-out is the only operation that can throw; the social SDK
    /// sign-outs are best-effort local cache clears and never throw.
    public func signOut() throws {
        // Clear social SDK sessions first (local, non-throwing) so a cached
        // Google/Facebook account isn't silently reused on the next sign-in.
        GIDSignIn.sharedInstance.signOut()
        LoginManager().logOut()

        do {
            try Auth.auth().signOut()
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Delete account

    /// Permanently deletes the currently signed-in Firebase account.
    ///
    /// Firebase requires a *recent* credential before a destructive operation.
    /// If the provider returns `requiresRecentLogin` we re-authenticate the
    /// user with the same provider they used to sign in, then retry deletion.
    public func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("No signed-in account to delete.")
        }

        do {
            try await user.delete()
            // Clear social SDK sessions on success.
            GIDSignIn.sharedInstance.signOut()
            LoginManager().logOut()
        } catch let error as NSError
            where AuthErrorCode(rawValue: error.code) == .requiresRecentLogin {
            // Re-authenticate with the same provider, then retry.
            try await reAuthenticateAndDelete(user: user)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    /// Re-authenticates the user using their linked provider, then deletes the
    /// account. Supports Apple, Google, Facebook, and email+password.
    @MainActor
    private func reAuthenticateAndDelete(user: User) async throws {
        let providerID = user.providerData.first?.providerID ?? ""
        guard let provider = Self.provider(forID: providerID) else {
            // Email+password — Firebase handles re-auth internally when the
            // user is linked only to the password provider; we surface a clear
            // message asking them to sign in again.
            throw AuthServiceError.message(
                "Please sign out and sign back in before deleting your account."
            )
        }

        do {
            let credential = try await freshCredential(for: provider)
            try await user.reauthenticate(with: credential)
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
            LoginManager().logOut()
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Credential factory

    /// Drives the native sign-in flow for `provider` and returns a fresh
    /// Firebase `AuthCredential`. Shared by re-authentication and linking.
    @MainActor
    private func freshCredential(for provider: SocialAuthProvider) async throws -> AuthCredential {
        switch provider {
        case .apple:
            let apple = try await AppleSignInCoordinator().signIn()
            return OAuthProvider.appleCredential(
                withIDToken: apple.idToken,
                rawNonce: apple.rawNonce,
                fullName: apple.fullName
            )
        case .google:
            return try await GoogleSignInCoordinator().signIn().credential
        case .facebook:
            try Self.ensureFacebookSDKReady()
            return try await FacebookSignInCoordinator().signIn().credential
        }
    }

    // MARK: - Session

    public var currentUser: AuthUser? {
        Auth.auth().currentUser.map { Self.mapUser($0) }
    }

    /// Bridges Firebase's `addStateDidChangeListener` to an `AsyncStream`.
    /// Emits the current user immediately and on every subsequent change.
    public func authStateStream() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield(user.map { Self.mapUser($0) })
            }
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }

    // MARK: - Account linking / provider bridging

    /// Links an additional social provider to the current account. Drives the
    /// provider's native sign-in to obtain a fresh credential, then calls
    /// Firebase's `user.link(with:)`. Re-authenticates and retries on
    /// `requiresRecentLogin`.
    @discardableResult
    @MainActor
    public func linkProvider(_ provider: SocialAuthProvider) async throws -> AuthUser {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to link an account.")
        }
        do {
            let credential = try await freshCredential(for: provider)
            do {
                let result = try await user.link(with: credential)
                return Self.mapUser(result.user)
            } catch let error as NSError
                where AuthErrorCode(rawValue: error.code) == .requiresRecentLogin {
                let recent = try await freshCredential(for: provider)
                try await user.reauthenticate(with: recent)
                let result = try await user.link(with: credential)
                return Self.mapUser(result.user)
            }
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    /// Removes a linked social provider. Firebase requires at least one sign-in
    /// method to remain on the account.
    @discardableResult
    @MainActor
    public func unlinkProvider(_ provider: SocialAuthProvider) async throws -> AuthUser {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to unlink an account.")
        }
        let providerID = Self.providerID(for: provider)
        guard user.providerData.count > 1 else {
            throw AuthServiceError.message(
                "Add another sign-in method before removing your only one."
            )
        }
        do {
            let updated = try await user.unlink(fromProvider: providerID)
            // Clear the matching SDK session so it isn't silently reused.
            if provider == .google { GIDSignIn.sharedInstance.signOut() }
            if provider == .facebook { LoginManager().logOut() }
            return Self.mapUser(updated)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // NOTE: `migrateProvider(from:to:)` is intentionally NOT overridden here.
    // AuthDomain provides a protocol-extension default that composes
    // `linkProvider` (safe, link-first) then `unlinkProvider`. Since both are
    // fully implemented above — including `requiresRecentLogin` re-auth retry
    // and the matching SDK-session cleanup on unlink — Firebase inherits a
    // correct, non-atomic migration for free. An override would only duplicate
    // those two calls; add one only if Firebase ever exposes a true atomic
    // swap or needs bespoke cleanup between the link and unlink steps.

    /// Re-authenticates the current user with the given provider.
    @MainActor
    public func reauthenticate(with provider: SocialAuthProvider) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to re-authenticate.")
        }
        do {
            let credential = try await freshCredential(for: provider)
            try await user.reauthenticate(with: credential)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    private static func providerID(for provider: SocialAuthProvider) -> String {
        switch provider {
        case .apple: return "apple.com"
        case .google: return "google.com"
        case .facebook: return "facebook.com"
        }
    }

    // MARK: - Email verification

    public func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to verify your email.")
        }
        do {
            try await user.sendEmailVerification()
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Profile & credential updates

    public func updateDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to update your profile.")
        }
        do {
            let change = user.createProfileChangeRequest()
            change.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try await change.commitChanges()
            // Firebase's state-did-change listener does not fire for profile
            // updates, so broadcast an explicit notification. Observers (e.g.
            // the dashboard hero header) refresh their derived name from it.
            let updated = Self.mapUser(user)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .authUserProfileDidChange, object: updated
                )
            }
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    public func updateEmail(_ email: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to update your email.")
        }
        do {
            // sendEmailVerification(beforeUpdatingEmail:) is the modern,
            // verified flow; Firebase updates the address once confirmed.
            try await user.sendEmailVerification(beforeUpdatingEmail: email)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    public func updatePassword(_ password: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.message("You must be signed in to update your password.")
        }
        do {
            try await user.updatePassword(to: password)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    // MARK: - Mapping

    private static func mapUser(_ user: User, fallbackName: String? = nil) -> AuthUser {
        let name = user.displayName?.nonEmpty ?? fallbackName?.nonEmpty
        return AuthUser(id: user.uid,
                        email: user.email,
                        displayName: name,
                        isEmailVerified: user.isEmailVerified,
                        linkedProviders: linkedProviders(of: user))
    }

    /// Maps Firebase `providerData` IDs to `SocialAuthProvider`. Email+password
    /// (`password`) and phone are intentionally excluded.
    private static func linkedProviders(of user: User) -> [SocialAuthProvider] {
        user.providerData.compactMap { Self.provider(forID: $0.providerID) }
    }

    private static func provider(forID id: String) -> SocialAuthProvider? {
        switch id {
        case "apple.com": return .apple
        case "google.com": return .google
        case "facebook.com": return .facebook
        default: return nil
        }
    }

    private static func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .long
        return formatter.string(from: components).nonEmpty
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
