import Foundation
import FirebaseFirestore

// MARK: - Enums

enum UserRole: String, Codable {
    case member
    case admin
}

// MARK: - VetoCharge

/// Tracks a single use of a Type 2 veto charge.
/// Each member has at most 2 charges; each has a 12-month cooldown from use.
struct VetoCharge: Codable, Equatable {
    var usedAt: Date
}

// MARK: - Member

/// Represents a BAAMF book club member (maps to Firestore `users/{userId}`).
struct Member: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    var name: String
    var email: String
    var role: UserRole
    var vetoCharges: [VetoCharge]
    var fcmToken: String?

    // MARK: Computed helpers

    /// Returns the number of veto charges currently available (not in 12-month cooldown).
    func availableVetoCharges(at date: Date = Date()) -> Int {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: date) ?? date
        let activeCharges = vetoCharges.filter { $0.usedAt > cutoff }
        return max(0, 2 - activeCharges.count)
    }

    var isAdmin: Bool { role == .admin }
}
