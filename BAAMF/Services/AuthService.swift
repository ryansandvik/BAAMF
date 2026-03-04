import Foundation
import Combine
import FirebaseAuth

/// Wraps Firebase Authentication. Publishes the raw Firebase user and exposes
/// sign-in / sign-out as async methods.
@MainActor
final class AuthService: ObservableObject {

    @Published private(set) var firebaseUser: FirebaseAuth.User?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        firebaseUser = Auth.auth().currentUser
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.firebaseUser = user
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth actions

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
}
