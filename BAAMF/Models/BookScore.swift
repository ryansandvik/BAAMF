import Foundation
import FirebaseFirestore

/// A member's score for the month's winning book (maps to `months/{monthId}/scores/{userId}`).
/// Scores are visible to all members (not anonymous).
struct BookScore: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    var bookId: String
    /// The scorer's user ID. (The document ID is also the userId, but kept here for convenience.)
    var scorerId: String
    /// Score on a 1–7 scale; half-points allowed (e.g. 3.5), though discouraged.
    var score: Double
    var updatedAt: Date
}
