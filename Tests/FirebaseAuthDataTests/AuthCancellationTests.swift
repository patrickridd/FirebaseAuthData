import Testing
@testable import FirebaseAuthData

/// Pins down the cancellation sentinel. Coordinators throw
/// `.message(AuthCancellation.sentinel)` when a user backs out of a social
/// sign-in, and the UI suppresses the error alert on this exact string — so if
/// the value ever drifts, cancelled sign-ins would surface as spurious errors.
@Suite("Auth cancellation sentinel")
struct AuthCancellationTests {

    @Test("Sentinel matches the agreed contract value")
    func sentinelIsStable() {
        #expect(AuthCancellation.sentinel == "com.superapp.featureauth.cancelled")
    }

    @Test("Sentinel is a non-empty, namespaced identifier")
    func sentinelIsWellFormed() {
        #expect(!AuthCancellation.sentinel.isEmpty)
        #expect(AuthCancellation.sentinel.contains("."))
    }
}
