import Foundation
import FirebaseFirestore

/// Represents a submitted book (maps to Firestore `months/{monthId}/books/{bookId}`).
struct Book: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    var title: String
    var author: String
    /// Description from Google Books, or overridden by the submitter with their own pitch.
    var description: String
    /// Submitter's custom pitch to the club (overrides `description` when set).
    var pitchOverride: String?
    var submitterId: String

    // Google Books metadata
    var googleBooksId: String
    var googleRating: Double?
    var pageCount: Int?
    var coverUrl: String?

    // Veto state
    /// Type 1 veto: book is immediately removed when true.
    var isRemovedByVeto: Bool
    /// User IDs who cast a Type 2 veto ("don't want to read") on this book.
    var vetoType2Voters: [String]
    /// True if the 25% threshold was met — book carries a -2 net vote penalty in R1.
    var vetoType2Penalty: Bool

    // Voting state
    /// User IDs who voted for this book in Round 1.
    var votingR1Voters: [String]
    /// User IDs who voted for this book in Round 2.
    var votingR2Voters: [String]
    /// Set to true when the host advances R1→R2 for the books that made the cut.
    var advancedToR2: Bool

    // MARK: Computed helpers

    /// The text to display in the book card — pitch if provided, otherwise Google Books description.
    var displayDescription: String {
        if let pitch = pitchOverride, !pitch.isEmpty { return pitch }
        return description
    }

    /// Net R1 votes: raw vote count minus the Hard Pass penalty if applicable.
    var r1NetVotes: Int {
        votingR1Voters.count + (vetoType2Penalty ? K.Veto.type2PenaltyVotes : 0)
    }

    /// Whether this book is eligible to be voted on in the current round.
    var isEligibleForR1: Bool { !isRemovedByVeto }
    var isEligibleForR2: Bool { advancedToR2 }
}
