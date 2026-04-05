import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

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
    var isObserver: Bool { currentMember?.isObserver ?? false }
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

        // Reload member profile after a successful profile picture upload
        NotificationCenter.default.publisher(for: .profileDidUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let uid = self?.currentUserId else { return }
                Task { @MainActor [weak self] in
                    await self?.loadMemberProfile(uid: uid)
                }
            }
            .store(in: &cancellables)

        // Persist the FCM token whenever the SDK rotates it
        NotificationCenter.default.publisher(for: .fcmTokenRefreshed)
            .compactMap { $0.object as? String }
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                guard let uid = self?.currentUserId else { return }
                NotificationService.shared.saveFCMToken(token, for: uid)
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
        if let uid = currentUserId {
            NotificationService.shared.clearFCMToken(for: uid)
        }
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

    func signUp(name: String, email: String, password: String, inviteCode: String) async {
        isLoading = true
        errorMessage = nil
        do {
            // ── 1. Validate invite code (pre-auth read) ───────────────────────
            let normalizedCode = inviteCode.uppercased().trimmingCharacters(in: .whitespaces)
            let codeSnap = try await firestoreService.inviteCodeRef(code: normalizedCode).getDocument()

            guard codeSnap.exists,
                  let data = codeSnap.data(),
                  data["usedAt"] == nil,
                  let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(),
                  expiresAt > Date()
            else {
                errorMessage = inviteCodeError(codeSnap)
                isLoading = false
                return
            }

            // ── 2. Create Firebase Auth account ───────────────────────────────
            let uid = try await authService.createUser(email: email, password: password)

            // ── 3. Batch-write user doc + mark code consumed ──────────────────
            let batch = firestoreService.db.batch()

            let userData: [String: Any] = [
                "name": name,
                "email": email,
                "role": UserRole.member.rawValue,
                "vetoCharges": []
            ]
            batch.setData(userData, forDocument: firestoreService.userRef(uid: uid))

            let codeUpdate: [String: Any] = [
                "usedAt": Timestamp(date: Date()),
                "usedBy": uid
            ]
            batch.updateData(codeUpdate, forDocument: firestoreService.inviteCodeRef(code: normalizedCode))

            try await batch.commit()
            // authStateHandle fires automatically and loads the member profile
        } catch {
            errorMessage = friendlyAuthError(error)
            isLoading = false
        }
    }

    // MARK: - Invite code generation (admin only)

    /// Generates a random 6-character invite code valid for 24 hours.
    /// Returns the plaintext code on success so the caller can display/copy it.
    func generateInviteCode() async throws -> String {
        guard let uid = currentUserId else { throw AppError.permissionDenied }
        let code = Self.randomCode()
        let data: [String: Any] = [
            "createdBy": uid,
            "createdAt": Timestamp(date: Date()),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(24 * 3600))
            // usedAt / usedBy intentionally omitted — absence means unused.
            // Writing NSNull() here causes data["usedAt"] != nil on read, which
            // makes every freshly generated code appear already consumed.
        ]
        try await firestoreService.inviteCodeRef(code: code).setData(data)
        return code
    }

    private static func randomCode(length: Int = 6) -> String {
        // Unambiguous character set (no 0/O, 1/I)
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - Profile

    private func loadMemberProfile(uid: String) async {
        do {
            currentMember = try await firestoreService.fetchMember(uid: uid)
        } catch {
            errorMessage = "Could not load your profile. Please try again."
        }
        isLoading = false

        // Observer accounts are read-only guests — skip notifications and FCM token
        // registration entirely so they don't receive push notifications.
        guard !(currentMember?.isObserver ?? false) else { return }

        // Request notification permission and save any already-available FCM token.
        // requestAuthorization() is a no-op after the first prompt.
        NotificationService.shared.requestAuthorization()
        if let token = Messaging.messaging().fcmToken {
            NotificationService.shared.saveFCMToken(token, for: uid)
        }
    }

    // MARK: - Error formatting

    private func inviteCodeError(_ snap: DocumentSnapshot) -> String {
        guard snap.exists, let data = snap.data() else {
            return "Invalid invite code. Please check the code and try again."
        }
        if data["usedAt"] != nil {
            return "This invite code has already been used."
        }
        if let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(), expiresAt <= Date() {
            return "This invite code has expired."
        }
        return "Invalid invite code."
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch AuthErrorCode(rawValue: code) {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found for that email."
        case .emailAlreadyInUse:
            return "An account already exists for that email."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .networkError:
            return "Network error. Check your connection and try again."
        default:
            return error.localizedDescription
        }
    }
}
