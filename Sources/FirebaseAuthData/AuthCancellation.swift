import Foundation

/// Shared sentinel used to mark a user-cancelled sign-in flow.
///
/// `AuthServiceError` (in AuthDomain 1.0.0) has no dedicated `.cancelled`
/// case, so coordinators throw `.message(AuthCancellation.sentinel)` and the
/// UI layer suppresses the alert when it sees this exact value. Keep this
/// string identical to the copy in the FeatureAuth package.
enum AuthCancellation {
    static let sentinel = "com.superapp.featureauth.cancelled"
}
