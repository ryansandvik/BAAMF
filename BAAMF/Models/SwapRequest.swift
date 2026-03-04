import Foundation
import FirebaseFirestore

enum SwapRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

/// A request to swap hosting months between two members.
/// Stored as an array field on the `hostSchedule/{year}` document.
struct SwapRequest: Identifiable, Codable, Equatable {
    var id: String
    var requesterId: String
    var targetId: String
    /// The month the requester wants to give up.
    var requesterMonth: Int
    /// The month the target member would give up (0 if requester just wants to offload their month).
    var targetMonth: Int
    var status: SwapRequestStatus
    var createdAt: Date
}
