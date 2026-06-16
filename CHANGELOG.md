# Changelog

All notable changes to FirebaseAuthData are documented here. This project
adheres to [Semantic Versioning](https://semver.org/).

## [1.5.0] - 2026-06-16

### Added
- **Account linking / provider bridging** — `linkProvider(_:)` drives the
  provider's native sign-in and calls Firebase `user.link(with:)`, keeping the
  same uid; re-authenticates and retries on `requiresRecentLogin`.
  `unlinkProvider(_:)` calls `user.unlink(fromProvider:)`, guards against
  removing the only sign-in method, and clears the matching Google/Facebook SDK
  session.
- **`reauthenticate(with:)`** — first-class re-auth via a shared
  `freshCredential(for:)` factory (also reused by deletion and linking).
- **Session** — `currentUser` maps the live Firebase user; `authStateStream()`
  bridges `addStateDidChangeListener` to an `AsyncStream<AuthUser?>` and removes
  the listener on termination.
- **Email verification** — `sendEmailVerification()`.
- **Profile & credential updates** — `updateDisplayName(_:)`,
  `updateEmail(_:)` (verified-update flow via
  `sendEmailVerification(beforeUpdatingEmail:)`), and `updatePassword(_:)`.
- **Richer `AuthUser` mapping** — now populates `isEmailVerified` and
  `linkedProviders` from Firebase `providerData`.

### Changed
- Bumped `AuthDomain` dependency to `from: "1.4.0"` for the new protocol surface.

---

## [1.4.0] - 2026-06-16

### Added
- **`FirebaseAuthService.deleteAccount()`** — implements the new `AuthService`
  protocol requirement. Deletes the current Firebase user and clears all
  social-SDK sessions (Google + Facebook) on success.
- **Re-authentication before deletion** — Firebase requires a recent credential
  for destructive operations. When the provider returns `requiresRecentLogin`,
  `deleteAccount()` automatically re-authenticates the user with their original
  provider (Apple, Google, or Facebook) and then retries the deletion. Email+
  password users are asked to sign out and back in before deleting.

### Changed
- Bumped `AuthDomain` dependency to `from: "1.3.0"` to satisfy the new
  `deleteAccount()` protocol requirement.

---

## [1.3.0] - 2026-06-14

### Added
- **`FirebaseAuthService.signOut()`** — clears all three provider sessions in
  one call: Google (`GIDSignIn.sharedInstance.signOut()`), Facebook
  (`LoginManager().logOut()`), and Firebase (`Auth.auth().signOut()`). Social
  SDK sign-outs are local, non-throwing cache clears; only Firebase can throw.
  Sign in with Apple requires no explicit sign-out (no local session to clear).

### Changed
- Bumped `AuthDomain` dependency to `from: "1.1.0"` to satisfy the new
  `signOut() throws` protocol requirement.

### Chore
- `Package.resolved` is now gitignored (library packages should not pin their
  transitive dependency graph).

---

## [1.2.1] - 2026-06-14

### Fixed
- **Facebook sign-in now uses Limited Login.** Under Apple's App Tracking
  Transparency, classic Facebook Login no longer returns a usable OAuth access
  token when the user hasn't granted tracking consent — the SDK silently
  redirects to `limited.facebook.com` and `result.token` comes back `nil`, so
  Firebase could not mint a credential and sign-in failed with a missing-token
  error. `FacebookSignInCoordinator` now requests Limited Login
  (`LoginConfiguration(permissions:tracking: .limited, nonce:)`) and exchanges
  the returned OIDC `AuthenticationToken` for a Firebase credential via
  `OAuthProvider.credential(providerID: .facebook, idToken:rawNonce:)`.

### Security
- A fresh cryptographically random **nonce** is generated per sign-in. Facebook
  receives only its SHA256 hash; the raw nonce is handed to Firebase so the
  returned token is verified as minted for this app (replay protection).

### Upgrade notes
- Landing on `limited.facebook.com` during the flow is now **expected and
  correct** — it is no longer an error.
- Ensure **Facebook is enabled in Firebase Console ▸ Authentication ▸ Sign-in
  method** with your App ID + App Secret. Firebase validates the Limited Login
  OIDC token against that configuration; a missing App Secret will reject
  otherwise-valid sign-ins.
- No host-app code changes are required; the `signIn(with: .facebook)` call site
  is unchanged.

## [1.2.0] - 2026-06-13

### Added
- **Social sign-in is now fully implemented** for all providers via
  `signIn(with:)`:
  - **Apple** — native `AuthenticationServices` flow exchanged for a Firebase
    credential.
  - **Google** — `GoogleSignIn` SDK flow exchanged for a Firebase credential.
  - **Facebook** — `FacebookLogin` SDK flow exchanged for a Firebase
    credential. The Facebook SDK is initialised lazily on first use (never at
    launch) to avoid startup bundle-ID validation crashes.
- `FirebaseAuthService.configureFacebook(application:launchOptions:)` and
  `handleOpenURL(_:options:)` helpers for wiring the Facebook SDK from your
  `AppDelegate` without importing the SDK in the host app.

### Fixed
- **User cancellation is now surfaced quietly.** When a user backs out of an
  Apple, Google, or Facebook sign-in, the coordinators emit a shared
  cancellation marker instead of a user-facing error message, so the UI can
  suppress the alert. Real failures are unaffected.

### Changed
- Migrated the test suite to Swift Testing (`@Suite`/`@Test`/`#expect`) and
  removed the obsolete "social not implemented" test now that all providers
  are wired.

## [1.1.0] - 2026-06-13

### Changed
- Raised the `firebase-ios-sdk` dependency floor to `12.14.0` (was `11.0.0`)
  to align with consumer apps on the Firebase 12 line and keep a single
  Firebase copy in the dependency graph. No public API or behavior changes.

### Upgrade notes
- Consumers must also move their direct `firebase-ios-sdk` requirement to
  `from: "12.14.0"` so SPM resolves one shared Firebase version. After
  updating, Reset Package Caches and Resolve Package Versions.

## [1.0.0] - 2026-06-11

### Added
- Initial public release of the Firebase-backed data layer — a concrete
  implementation of the `AuthService` contract from `AuthDomain`.
- `FirebaseAuthService` — adapts the `FirebaseAuth` SDK to the
  backend-agnostic `AuthService` protocol, keeping the UI layer
  (`FeatureAuth`) free of any Firebase imports.
- Email + password sign-in (`signIn(email:password:)`).
- Email + password registration (`signUp(firstName:lastName:email:password:)`),
  which also sets the user's Firebase display name.
- Password reset (`sendPasswordReset(email:)`).
- Friendly error mapping — `AuthErrorCode` values are translated into
  localized, user-facing `AuthServiceError.message` strings so the UI never
  needs to know about Firebase error domains.
- `User` → `AuthUser` mapping, including display-name fallback on sign-up.
- Unit tests covering `AuthService` conformance and the `notImplemented`
  social-provider behavior.

### Not yet implemented
- Social sign-in (`signIn(with:)`) currently throws
  `AuthServiceError.notImplemented` per provider. Apple and Google providers
  are planned for the `1.2.0` minor release once their SDKs are wired in.
