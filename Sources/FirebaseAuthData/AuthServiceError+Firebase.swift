import Foundation
import AuthDomain
import FirebaseAuth

extension AuthServiceError {

    /// Maps a Firebase `AuthErrorCode` (or any error) to a friendly
    /// `AuthServiceError.message`, so the UI never has to know about Firebase.
    static func from(_ error: Error) -> AuthServiceError {
        if let existing = error as? AuthServiceError { return existing }

        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return .message(nsError.localizedDescription)
        }

        switch code {
        case .invalidEmail:
            return .message("That email address doesn't look right.")
        case .emailAlreadyInUse:
            return .message("An account already exists with this email.")
        case .weakPassword:
            return .message("Please choose a stronger password (at least 6 characters).")
        case .wrongPassword, .invalidCredential:
            return .message("Incorrect email or password.")
        case .userNotFound:
            return .message("No account found with this email.")
        case .userDisabled:
            return .message("This account has been disabled.")
        case .tooManyRequests:
            return .message("Too many attempts. Please try again later.")
        case .networkError:
            return .message("Network error. Check your connection and try again.")
        default:
            return .message(nsError.localizedDescription)
        }
    }
}
