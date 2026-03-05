import Foundation
import Combine
import FirebaseFirestore

/// Manages per-user notification preferences stored in `users/{uid}.notificationPrefs`.
///
/// Preferences default to `true` (opted in) when no Firestore value exists.
/// Toggling any switch auto-saves the full prefs map immediately.
@MainActor
final class NotificationPrefsViewModel: ObservableObject {

    // MARK: - Preferences (all default on)

    @Published var nominations: Bool = true  // submissions, vetoes, voting_r1, voting_r2
    @Published var reading:     Bool = true  // reading phase (book announced)
    @Published var scoring:     Bool = true  // scoring phase
    @Published var swaps:       Bool = true  // host swap requests targeting this user

    // MARK: - Status

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = FirestoreService.shared
    private let userId: String
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Load

    func load() {
        isLoading = true
        Task {
            do {
                let doc = try await db.userRef(uid: userId).getDocument()
                if let prefs = doc.data()?["notificationPrefs"] as? [String: Bool] {
                    nominations = prefs["nominations"] ?? true
                    reading     = prefs["reading"]     ?? true
                    scoring     = prefs["scoring"]     ?? true
                    swaps       = prefs["swaps"]       ?? true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Save (debounced — called after each toggle)

    /// Cancels any pending save and schedules a fresh one. This debounces
    /// rapid successive toggles into a single Firestore write.
    func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            // Short delay so rapid taps merge into one write
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            guard !Task.isCancelled else { return }
            await persistPrefs()
        }
    }

    // MARK: - Private

    private func persistPrefs() async {
        do {
            let prefs: [String: Any] = [
                "notificationPrefs": [
                    "nominations": nominations,
                    "reading":     reading,
                    "scoring":     scoring,
                    "swaps":       swaps
                ]
            ]
            try await db.userRef(uid: userId).updateData(prefs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
