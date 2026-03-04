import Foundation
import FirebaseFirestore

/// A member's Round 1 vote (maps to `months/{monthId}/votes_r1/{userId}`).
/// Each member distributes exactly 2 votes across eligible books.
/// Security rules: only the owning user can read/write their own document.
struct VoteR1: Codable {
    /// The two book IDs the member voted for (may be the same book twice if desired — TBD by rules).
    var bookVotes: [String]
    var createdAt: Date
}

/// A member's Round 2 vote (maps to `months/{monthId}/votes_r2/{userId}`).
/// Each member casts exactly 1 vote.
struct VoteR2: Codable {
    var bookId: String
    var createdAt: Date
}
