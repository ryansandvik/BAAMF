import Foundation
import SwiftUI

// MARK: - Date helpers

extension Date {
    /// Rounds the minutes component down to the nearest `interval` (e.g. 5).
    /// Seconds are always zeroed. Used to enforce 5-minute picker granularity.
    func snappedToMinuteInterval(_ interval: Int) -> Date {
        guard interval > 1 else { return self }
        var comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: self
        )
        let m = comps.minute ?? 0
        comps.minute  = (m / interval) * interval
        comps.second  = 0
        return Calendar.current.date(from: comps) ?? self
    }

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
    static let scoresDidUpdate      = Notification.Name("scoresDidUpdate")
    /// Posted by HomeViewModel (via UIApplication willEnterForeground) to re-sync
    /// calendar events regardless of which tab is currently visible.
    static let appWillEnterForeground = Notification.Name("appWillEnterForeground")

    /// Posted by ProfilePictureViewModel after a successful photo upload,
    /// so AuthViewModel reloads the member profile with the new photoURL.
    static let profileDidUpdate = Notification.Name("profileDidUpdate")
}

// MARK: - View helpers

extension View {
    /// Conditionally applies a modifier.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    /// Applies the standard card appearance: grouped background, rounded corners,
    /// a hairline border for contrast in light mode, and a subtle shadow.
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Card style modifier

private struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.06 : 0),
                radius: 6, x: 0, y: 2
            )
    }
}
