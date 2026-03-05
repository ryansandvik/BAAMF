import Foundation
import EventKit

/// Manages BAAMF event entries in the user's default iOS calendar.
///
/// Implemented as an `actor` so concurrent calls from multiple Firestore
/// snapshot listeners never race and accidentally create duplicate events.
///
/// Events are tracked two ways:
///   1. **In-memory cache** (`eventCache`) — authoritative for the current session.
///      Phase changes, book selection, and location edits all update the same
///      `EKEvent` object without ever hitting the EventKit store for a lookup.
///   2. **UserDefaults** — persists the event identifier across app launches so
///      the in-memory cache can be rebuilt the first time `syncEvent` runs after
///      a cold start.
actor CalendarService {

    static let shared = CalendarService()

    private let store = EKEventStore()

    /// Keyed by monthId ("2026-03"). Holds the live EKEvent for this session.
    private var eventCache: [String: EKEvent] = [:]

    private init() {}

    // MARK: - Public API

    /// Creates or updates the calendar event for the given month.
    /// Silently does nothing if `eventDate` is nil or the user denies access.
    func syncEvent(for month: ClubMonth) async {
        guard let startDate = month.eventDate else {
            // Event date was removed — delete whatever we had
            removeEvent(for: resolvedMonthId(for: month))
            return
        }

        guard await requestWriteAccess() else { return }

        let monthId = resolvedMonthId(for: month)

        // ── Locate existing event ─────────────────────────────────────────────
        // Priority: in-memory cache → UserDefaults identifier → create new
        var event: EKEvent? = eventCache[monthId]

        if event == nil {
            if let storedId = UserDefaults.standard.string(forKey: calendarKey(for: monthId)) {
                event = store.event(withIdentifier: storedId)
            }
        }

        if event == nil {
            let newEvent = EKEvent(eventStore: store)
            newEvent.calendar = store.defaultCalendarForNewEvents
            event = newEvent
        }

        guard let event else { return }

        // ── Update all fields ─────────────────────────────────────────────────
        let monthSymbols = Calendar.current.monthSymbols
        let monthIndex = max(1, min(12, month.month)) - 1
        let monthName = "\(monthSymbols[monthIndex]) \(month.year)"
        if let bookTitle = month.selectedBookTitle, !bookTitle.isEmpty {
            event.title = "BAAMF — \(bookTitle)"
        } else {
            event.title = "BAAMF — \(monthName)"
        }

        event.startDate = startDate
        event.endDate   = month.eventEndDate
            ?? Calendar.current.date(byAdding: .hour, value: 2, to: startDate)
            ?? startDate
        event.location  = month.eventLocation
        event.notes     = month.eventNotes

        // ── Persist ───────────────────────────────────────────────────────────
        do {
            try store.save(event, span: .thisEvent)
            eventCache[monthId] = event  // Keep alive for this session
            UserDefaults.standard.set(event.eventIdentifier,
                                      forKey: calendarKey(for: monthId))
        } catch {
            print("CalendarService: save failed – \(error.localizedDescription)")
        }
    }

    /// Removes the calendar event for a month (called when the event date is cleared).
    func removeEvent(for monthId: String) {
        let existing: EKEvent? = eventCache[monthId] ?? {
            guard let storedId = UserDefaults.standard.string(forKey: calendarKey(for: monthId))
            else { return nil }
            return store.event(withIdentifier: storedId)
        }()

        if let existing {
            try? store.remove(existing, span: .thisEvent)
        }
        eventCache.removeValue(forKey: monthId)
        UserDefaults.standard.removeObject(forKey: calendarKey(for: monthId))
    }

    // MARK: - Private helpers

    private func calendarKey(for monthId: String) -> String {
        "baamf-calendarEvent-\(monthId)"
    }

    private func resolvedMonthId(for month: ClubMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
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
