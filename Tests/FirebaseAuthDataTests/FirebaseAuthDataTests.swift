import Testing
import AuthDomain
@testable import FirebaseAuthData

@Suite("FirebaseAuthService")
struct FirebaseAuthDataTests {

    @Test("FirebaseAuthService satisfies the AuthService contract")
    func conformsToAuthService() {
        // Given / When
        let service: AuthService = FirebaseAuthService()

        // Then
        #expect(service is FirebaseAuthService)
    }
}
