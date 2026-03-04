import Foundation
import FirebaseFirestore

/// The host schedule for a given year (maps to Firestore `hostSchedule/{year}`).
/// `assignments` maps month number (1–12) as a String key to a member's userId.
struct HostSchedule: Identifiable, Codable {
    @DocumentID var id: String?  // The year as a string, e.g. "2026"

    /// Month number (String "1"–"12") → userId
    var assignments: [String: String]

    /// Returns the userId of the host for the given month number.
    func hostId(for month: Int) -> String? {
        assignments[String(month)]
    }

    /// Returns the month numbers (1–12) hosted by the given userId.
    func months(for userId: String) -> [Int] {
        assignments.compactMap { key, value in
            value == userId ? Int(key) : nil
        }.sorted()
    }
}
