import Foundation
import AuthDomain
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import FacebookLogin

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
            NSLog("FirebaseAuthService: GoogleService-Info.plist not found — Firebase not configured.")
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
            NSLog("FirebaseAuthService: CLIENT_ID missing from GoogleService-Info.plist — Google Sign-In won't work.")
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
        NSLog("FirebaseAuthService: FB lazy init bundleID='\(Bundle.main.bundleIdentifier ?? "?")' appID='\(fbAppID)' tokenLen=\(fbToken.count)")
        guard !fbAppID.isEmpty, !fbToken.isEmpty else {
            throw AuthServiceError.message("Facebook Sign-In is not configured (missing plist keys).")
        }
        ApplicationDelegate.shared.application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: nil
        )
        facebookSDKReady = true
        NSLog("FirebaseAuthService: Facebook SDK ready.")
    }

    /// No-op at launch — Facebook SDK is initialised lazily on first sign-in.
    /// Kept for AppDelegate API compatibility.
    @MainActor
    public static func configureFacebook(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) {
        NSLog("FirebaseAuthService: Facebook init deferred to first sign-in attempt.")
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

    // MARK: - Mapping

    private static func mapUser(_ user: User, fallbackName: String? = nil) -> AuthUser {
        let name = user.displayName?.nonEmpty ?? fallbackName?.nonEmpty
        return AuthUser(id: user.uid, email: user.email, displayName: name)
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
