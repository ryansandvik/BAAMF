import Foundation
import FirebaseFirestore

// MARK: - Enums

enum MonthStatus: String, Codable, CaseIterable, Hashable {
    case setup
    case submissions
    case vetoes
    case votingR1 = "voting_r1"
    case votingR2 = "voting_r2"
    case reading
    case scoring
    case complete

    var displayName: String {
        switch self {
        case .setup:        return "Setup"
        case .submissions:  return "Submissions Open"
        case .vetoes:       return "Veto Window"
        case .votingR1:     return "Voting — Round 1"
        case .votingR2:     return "Voting — Round 2"
        case .reading:      return "Reading"
        case .scoring:      return "Scoring"
        case .complete:     return "Complete"
        }
    }
}

enum SubmissionMode: String, Codable, Hashable {
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
struct ClubMonth: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?

    var year: Int
    var month: Int
    var hostId: String
    var submissionMode: SubmissionMode
    var theme: String?
    var eventDate: Date?
    var eventEndDate: Date?
    var eventLocation: String?
    var eventNotes: String?
    var isHistorical: Bool?
    var status: MonthStatus
    var winningBookId: String?
    var groupAvgScore: Double?

    // The book chosen at the end of Round 2. Written when the host advances to Reading.
    var selectedBookId: String?
    var selectedBookTitle: String?
    var selectedBookAuthor: String?
    var selectedBookCoverUrl: String?
    /// The uid of the member who submitted the winning book.
    /// Nil for historical entries and for host-select-4 months where the host
    /// chose from their own submissions. Only revealed in UI once status reaches .reading.
    var selectedBookSubmitterId: String?

    // Phase deadlines — set when each phase opens; the Cloud Scheduler auto-advances
    // the month when the deadline passes. Not applicable in hostSelect4 mode.
    var submissionDeadline: Date?
    var vetoDeadline: Date?
    var votingR1Deadline: Date?
    var votingR2Deadline: Date?

    // MARK: Computed helpers

    /// The active deadline for the current phase, if one is set.
    var activeDeadline: Date? {
        switch status {
        case .submissions: return submissionDeadline
        case .vetoes:      return vetoDeadline
        case .votingR1:    return votingR1Deadline
        case .votingR2:    return votingR2Deadline
        default:           return nil
        }
    }

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
