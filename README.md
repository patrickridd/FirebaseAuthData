# FirebaseAuthData

The **Firebase-backed data layer** for auth — a concrete implementation of the
[`AuthService`](https://github.com/patrickridd/AuthDomain) contract.

This package is the seam's *implementation* side: it adapts Firebase's
`FirebaseAuth` SDK to the backend-agnostic `AuthService` protocol from
`AuthDomain`. The UI layer (`FeatureAuth`) depends only on the contract and
never imports Firebase — keeping it pure, testable, and provider-agnostic.

```
AuthDomain  ←  FeatureAuth        (UI, contract only)
    ↑
FirebaseAuthData  →  FirebaseAuth (this package, the implementation)
```

## Requirements

- iOS 17+
- Swift 5.9+
- A Firebase project with `GoogleService-Info.plist`

## Installation

Add via Swift Package Manager:

```swift
.package(url: "https://github.com/patrickridd/FirebaseAuthData.git", from: "1.0.0")
```

This package brings in `AuthDomain` and the Firebase iOS SDK transitively.

> **Version alignment:** if your app also depends on `FeatureAuth`, make sure
> both packages resolve to the **same major version** of `AuthDomain`
> (currently `1.x`). Mismatched majors will cause a Swift Package Manager
> resolution conflict, since both must share a single `AuthDomain`.

## Firebase project setup

This package adapts the Firebase SDK but does **not** configure Firebase for
you — that's the host app's responsibility. Before using `FirebaseAuthService`:

1. Create a project in the [Firebase Console](https://console.firebase.google.com).
2. Add an iOS app to the project using your app's bundle identifier.
3. Download the generated `GoogleService-Info.plist` and add it to your **app
   target** (not this package).
4. Enable **Email/Password** under *Authentication → Sign-in method*.
5. Call `FirebaseApp.configure()` once at launch (see *Usage* below).

## Usage

Configure Firebase once at launch, then inject `FirebaseAuthService` wherever
the auth UI expects an `AuthService`:

```swift
import FirebaseCore
import FirebaseAuthData
import FeatureAuth

@main
struct MyApp: App {
    init() { FirebaseApp.configure() }

    var body: some Scene {
        WindowGroup {
            AuthFlowView(
                config: .init(appName: "My App"),
                service: FirebaseAuthService()
            ) { user in
                // handle authenticated user
            }
        }
    }
}
```

## What's implemented

| Capability | Status |
|---|---|
| Email + password sign-in | ✅ |
| Email + password sign-up (sets display name) | ✅ |
| Password reset | ✅ |
| Friendly error mapping (`AuthErrorCode` → `AuthServiceError`) | ✅ |
| Social sign-in — Apple | ✅ |
| Social sign-in — Google | ✅ |
| Social sign-in — Facebook (Limited Login) | ✅ |

All three social providers are fully wired and exchange their native SDK result
for a Firebase `AuthCredential` behind the backend-agnostic `signIn(with:)` API.

### Facebook uses Limited Login

Facebook sign-in uses **Limited Login**, not classic OAuth. This is required by
Apple's App Tracking Transparency: without tracking consent the classic flow no
longer returns a usable access token, so the SDK redirects to
`limited.facebook.com` and Firebase can't mint a credential from it.

Instead, the coordinator:

1. Generates a random **nonce** per sign-in and sends Facebook its **SHA256
   hash** via `LoginConfiguration(permissions:tracking: .limited, nonce:)`.
2. Reads the returned OIDC `AuthenticationToken` (Limited Login does **not**
   return an access token).
3. Builds the Firebase credential with the **raw** nonce:
   `OAuthProvider.credential(providerID: .facebook, idToken:rawNonce:)`.

**Setup:** enable **Facebook** in *Firebase Console ▸ Authentication ▸ Sign-in
method* with your **App ID + App Secret** — Firebase validates the OIDC token
against it. Landing on `limited.facebook.com` during sign-in is expected and
correct.

## Versioning

This package follows [Semantic Versioning](https://semver.org). See
[CHANGELOG.md](CHANGELOG.md) for release notes. Additive capabilities (such as
social sign-in) ship as **minor** releases; breaking changes to the
`AuthService` surface that ripple from `AuthDomain` ship as **major** releases.

## License

[MIT](LICENSE)
