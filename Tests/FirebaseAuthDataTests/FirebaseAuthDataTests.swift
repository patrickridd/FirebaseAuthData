import XCTest
import AuthDomain
@testable import FirebaseAuthData

final class FirebaseAuthDataTests: XCTestCase {

    /// `FirebaseAuthService` should conform to the `AuthService` contract.
    func testConformsToAuthService() {
        let service: AuthService = FirebaseAuthService()
        XCTAssertNotNil(service)
    }

    /// Social sign-in is not wired yet and should report `notImplemented`.
    func testSocialSignInNotImplemented() async {
        let service = FirebaseAuthService()
        do {
            _ = try await service.signIn(with: .google)
            XCTFail("Expected notImplemented error")
        } catch let error as AuthServiceError {
            if case .notImplemented = error {
                // expected
            } else {
                XCTFail("Expected notImplemented, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
