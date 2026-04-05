import Foundation
import FirebaseFirestore

/// One member's RSVP for a given month.
/// Stored at `months/{monthId}/attendance/{userId}`.
struct AttendanceRecord: Identifiable, Codable, Equatable {
    /// The document ID is the member's uid.
    @DocumentID var id: String?

    var attending: Bool
    var updatedAt: Date
    /// When true the member has indicated they might come but aren't sure.
    /// Maybes are grouped with no-response for roll call purposes.
    var isMaybe: Bool?
}
