import Foundation
import FirebaseFirestore

enum SwapRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

/// A request to swap hosting months between two members.
/// Stored in the `hostSchedule/{year}/swapRequests/{requestId}` subcollection.
struct SwapRequest: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    var requesterId: String
    var targetId: String
    /// The month the requester wants to give up.
    var requesterMonth: Int
    /// The month the target member would give up (0 means offload only — no return swap).
    var targetMonth: Int
    var status: SwapRequestStatus
    var createdAt: Date
}
