import Foundation
import EventKit
import UIKit

/// Manages BAAMF event entries in the user's default iOS calendar.
///
/// Each month's event identifier is persisted in `UserDefaults` so the same
/// EKEvent can be found and updated when the host edits the date, location,
/// or notes, and when the book title is chosen.
final class CalendarService {

    static let shared = CalendarService()

    private let store = EKEventStore()
    private let defaultDurationHours: Double = 2

    private init() {}

    // MARK: - Public API

    /// Creates or updates a calendar event for the given month.
    /// - Does nothing if `month.eventDate` is nil.
    /// - Silently skips if the user denies calendar access.
    /// - Must be called on any actor; EventKit access is handled internally.
    func syncEvent(for month: ClubMonth) async {
        guard let startDate = month.eventDate else {
            // If the event date was removed, delete the existing calendar event
            if let monthId = month.id { removeEvent(for: monthId) }
            return
        }

        guard await requestWriteAccess() else { return }

        let monthId = month.id ?? ClubMonth.monthId(year: month.year, month: month.month)
        let storageKey = calendarKey(for: monthId)

        // Find or create the EKEvent
        let event: EKEvent
        if let existingId = UserDefaults.standard.string(forKey: storageKey),
           let existing = store.event(withIdentifier: existingId) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = store.defaultCalendarForNewEvents
        }

        // Build the title: use book title once chosen, month name until then
        let monthName = "\(month.month.monthName) \(month.year)"
        if let bookTitle = month.selectedBookTitle, !bookTitle.isEmpty {
            event.title = "BAAMF — \(bookTitle)"
        } else {
            event.title = "BAAMF — \(monthName)"
        }

        event.startDate = startDate
        event.endDate   = month.eventEndDate
            ?? Calendar.current.date(
                byAdding: .hour,
                value: Int(defaultDurationHours),
                to: startDate
            ) ?? startDate

        event.location = month.eventLocation
        event.notes    = month.eventNotes

        do {
            try store.save(event, span: .thisEvent)
            // Persist the identifier so future updates can find this event
            UserDefaults.standard.set(event.eventIdentifier, forKey: storageKey)
        } catch {
            print("CalendarService: failed to save event – \(error.localizedDescription)")
        }
    }

    /// Removes the calendar event for a month (e.g. when the event date is cleared).
    func removeEvent(for monthId: String) {
        let key = calendarKey(for: monthId)
        guard let existingId = UserDefaults.standard.string(forKey: key),
              let event = store.event(withIdentifier: existingId) else { return }
        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            print("CalendarService: failed to remove event – \(error.localizedDescription)")
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Private helpers

    private func calendarKey(for monthId: String) -> String {
        "baamf-calendarEvent-\(monthId)"
    }

    private func requestWriteAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
