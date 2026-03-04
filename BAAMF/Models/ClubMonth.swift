import Foundation
import FirebaseFirestore

// MARK: - Enums

enum MonthStatus: String, Codable, CaseIterable {
    case setup
    case submissions
    case vetoes
    case votingR1 = "voting_r1"
    case votingR2 = "voting_r2"
    case scoring
    case complete

    var displayName: String {
        switch self {
        case .setup:        return "Setup"
        case .submissions:  return "Submissions Open"
        case .vetoes:       return "Veto Window"
        case .votingR1:     return "Voting — Round 1"
        case .votingR2:     return "Voting — Round 2"
        case .scoring:      return "Scoring"
        case .complete:     return "Complete"
        }
    }
}

enum SubmissionMode: String, Codable {
    case open
    case theme
    case pick4

    var displayName: String {
        switch self {
        case .open:   return "Open"
        case .theme:  return "Theme"
        case .pick4:  return "Host Pick-4"
        }
    }

    var description: String {
        switch self {
        case .open:
            return "Any member may submit one book."
        case .theme:
            return "Any member may submit one book fitting the host's theme."
        case .pick4:
            return "The host submits exactly 4 books. Other members don't submit."
        }
    }
}

// MARK: - ClubMonth

/// Represents one monthly book club cycle (maps to Firestore `months/{monthId}`).
/// The document ID format is "YYYY-MM" (e.g. "2026-03").
struct ClubMonth: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    var year: Int
    var month: Int
    var hostId: String
    var submissionMode: SubmissionMode
    var theme: String?
    var eventDate: Date?
    var eventLocation: String?
    var eventNotes: String?
    var status: MonthStatus
    var winningBookId: String?
    var groupAvgScore: Double?

    // MARK: Computed helpers

    /// The canonical Firestore document ID for the given year/month.
    static func monthId(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// The document ID for the current calendar month.
    static func currentMonthId() -> String {
        let now = Date()
        let cal = Calendar.current
        return monthId(year: cal.component(.year, from: now),
                       month: cal.component(.month, from: now))
    }

    /// Whether the given user is the host for this month.
    func isHost(userId: String) -> Bool { hostId == userId }

    /// Whether a user can control status transitions (host or admin check happens in views/VMs).
    var isVotingOpen: Bool { status == .votingR1 || status == .votingR2 }
}
