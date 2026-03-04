import Foundation
import Combine
import FirebaseAuth

/// Owns the auth lifecycle and the current member's Firestore profile.
/// Injected as an `@EnvironmentObject` at the app root so all views can
/// read the current user's role without additional fetches.
@MainActor
final class AuthViewModel: ObservableObject {

    @Published private(set) var currentMember: Member?
    @Published private(set) var isAuthenticated = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let authService = AuthService()
    private let firestoreService = FirestoreService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Convenience accessors

    var currentUserId: String? { authService.firebaseUser?.uid }
    var isAdmin: Bool { currentMember?.isAdmin ?? false }
    var isHost: Bool = false  // Set by HomeViewModel when viewing current month

    // MARK: - Init

    init() {
        authService.$firebaseUser
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let user {
                        await self.loadMemberProfile(uid: user.uid)
                        self.isAuthenticated = true
                    } else {
                        self.currentMember = nil
                        self.isAuthenticated = false
                        self.isLoading = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Auth actions

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = friendlyAuthError(error)
            isLoading = false
        }
    }

    func signOut() {
        errorMessage = nil
        try? authService.signOut()
    }

    func sendPasswordReset(email: String) async {
        do {
            try await authService.sendPasswordReset(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile

    private func loadMemberProfile(uid: String) async {
        do {
            currentMember = try await firestoreService.fetchMember(uid: uid)
        } catch {
            errorMessage = "Could not load your profile. Please try again."
        }
        isLoading = false
    }

    // MARK: - Error formatting

    private func friendlyAuthError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch AuthErrorCode(rawValue: code) {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found for that email."
        case .networkError:
            return "Network error. Check your connection and try again."
        default:
            return error.localizedDescription
        }
    }
}
