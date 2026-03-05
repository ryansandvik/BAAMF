import Foundation
import FirebaseFirestore

// MARK: - Enums

enum UserRole: String, Codable {
    case member
    case admin
}

// MARK: - VetoCharge

/// Tracks a single use of a Hard Pass veto charge.
/// Cooldown is month-based: a charge used in June 2025 becomes available again June 1, 2026,
/// regardless of the day it was used. This prevents book clubs that meet late in the month
/// from losing access to their charge earlier than intended.
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

    /// Returns the number of Hard Pass charges currently available.
    /// Cooldown is month-based: a charge used in month M becomes available on the 1st of month M
    /// one year later. e.g. used June 29, 2025 → available June 1, 2026.
    func availableVetoCharges(at date: Date = Date()) -> Int {
        let coolingCount = vetoCharges.filter { isChargeCooling($0, at: date) }.count
        return max(0, K.Veto.maxCharges - coolingCount)
    }

    /// The earliest date a cooling charge comes off cooldown, or nil if all charges are available.
    func nextHardPassChargeDate(at date: Date = Date()) -> Date? {
        let cooldownDates = vetoCharges.compactMap { charge -> Date? in
            guard let available = chargeAvailableDate(charge) else { return nil }
            return date < available ? available : nil
        }
        return cooldownDates.min()
    }

    // MARK: - Private charge helpers

    /// A charge is cooling if today is before its month-aligned availability date.
    private func isChargeCooling(_ charge: VetoCharge, at date: Date) -> Bool {
        guard let available = chargeAvailableDate(charge) else { return false }
        return date < available
    }

    /// The date a charge comes off cooldown: the 1st of the same calendar month, one year later.
    private func chargeAvailableDate(_ charge: VetoCharge) -> Date? {
        let cal = Calendar.current
        // Strip the day — normalize to the 1st of the month the charge was used
        let components = cal.dateComponents([.year, .month], from: charge.usedAt)
        guard let monthStart = cal.date(from: components) else { return nil }
        return cal.date(byAdding: .month, value: K.Veto.cooldownMonths, to: monthStart)
    }

    var isAdmin: Bool { role == .admin }
}
