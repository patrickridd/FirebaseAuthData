# Changelog

All notable changes to FirebaseAuthData are documented here. This project
adheres to [Semantic Versioning](https://semver.org/).

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
