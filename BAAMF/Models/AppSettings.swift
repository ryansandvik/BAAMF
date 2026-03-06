import Foundation
import FirebaseFirestore

/// App-wide defaults stored at `settings/defaults` in Firestore.
/// Admins configure these; they pre-fill the deadline DatePicker when a phase opens.
struct AppSettings: Codable {

    /// Default number of days for the Submissions phase.
    var submissionDays: Int = 7
    /// Default number of days for the Veto Window phase.
    var vetoDays: Int = 2
    /// Default number of days for Voting Round 1.
    var votingR1Days: Int = 2
    /// Default number of days for Voting Round 2.
    var votingR2Days: Int = 2

    /// Returns the proposed deadline date for a given target phase using the stored defaults.
    /// Returns nil for phases that don't have deadlines (reading, scoring, complete, setup).
    func defaultDeadline(for status: MonthStatus) -> Date? {
        let days: Int?
        switch status {
        case .submissions: days = submissionDays
        case .vetoes:      days = vetoDays
        case .votingR1:    days = votingR1Days
        case .votingR2:    days = votingR2Days
        default:           days = nil
        }
        guard let d = days else { return nil }
        return Calendar.current.date(byAdding: .day, value: d, to: Date())
    }
}
