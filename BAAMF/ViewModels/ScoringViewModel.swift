import Foundation
import Combine
import FirebaseFirestore

/// Manages real-time score data for the scoring phase.
/// Each member writes their own score to `months/{monthId}/scores/{userId}`.
/// Scores are visible to all members (not anonymous).
@MainActor
final class ScoringViewModel: ObservableObject {

    @Published private(set) var scores: [BookScore] = []
    @Published var isLoading = true
    @Published var isActing = false
    @Published var errorMessage: String?

    private let db = FirestoreService.shared
    private var listener: ListenerRegistration?

    // MARK: - Lifecycle

    func start(monthId: String) {
        isLoading = true
        listener = db.scoresRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.scores = snapshot?.documents
                        .compactMap { try? $0.data(as: BookScore.self) } ?? []
                }
            }
    }

    func stop() { listener?.remove() }
    deinit { listener?.remove() }

    // MARK: - Derived state

    /// The current user's submitted score, if any.
    func myScore(userId: String) -> Double? {
        scores.first { $0.scorerId == userId }?.score
    }

    /// True if the given user has submitted a score.
    func hasScored(userId: String) -> Bool {
        scores.contains { $0.scorerId == userId }
    }

    /// Live group average across all submitted scores.
    var groupAverage: Double? {
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0) { $0 + $1.score } / Double(scores.count)
    }

    // MARK: - Submit / update score

    /// Writes (or overwrites) the user's score for the month's selected book.
    func submitScore(_ score: Double,
                     monthId: String,
                     bookId: String,
                     userId: String) async {
        isActing = true
        errorMessage = nil
        let data: [String: Any] = [
            "bookId":    bookId,
            "scorerId":  userId,
            "score":     score,
            "updatedAt": Timestamp(date: Date())
        ]
        do {
            try await db.scoresRef(monthId: monthId)
                .document(userId)
                .setData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }
}
