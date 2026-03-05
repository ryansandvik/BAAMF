import Foundation
import SwiftUI

// MARK: - Date helpers

extension Date {
    /// "March 2026" style display string for a month document.
    func monthYearDisplay() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: self)
    }

    /// The "YYYY-MM" Firestore document ID for this date's month.
    var monthId: String {
        let cal = Calendar.current
        return String(format: "%04d-%02d",
                      cal.component(.year, from: self),
                      cal.component(.month, from: self))
    }
}

// MARK: - Int (month) helpers

extension Int {
    /// Full month name for a 1–12 integer.
    var monthName: String {
        DateFormatter().monthSymbols[self - 1]
    }
}

// MARK: - Double (score) helpers

extension Double {
    /// Formats a score as "4" or "4.5" (drops trailing .0 for whole numbers).
    var scoreDisplay: String {
        self.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.1f", self)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by EditCompletedMonthViewModel after a successful score save,
    /// so any listening VM (e.g. FavoriteBooksViewModel) can refresh.
    static let scoresDidUpdate = Notification.Name("scoresDidUpdate")
}

// MARK: - View helpers

extension View {
    /// Conditionally applies a modifier.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
