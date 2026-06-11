# Changelog

All notable changes to FirebaseAuthData are documented here. This project
adheres to [Semantic Versioning](https://semver.org/).

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
  are planned for a future minor release once their SDKs are wired in.
