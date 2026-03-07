import Foundation
import EventKit
import FirebaseFirestore

/// Manages BAAMF event entries in the user's default iOS calendar.
///
/// Implemented as an `actor` so concurrent calls from multiple Firestore
/// snapshot listeners never race and accidentally create duplicate events.
///
/// Events are tracked three ways (lookup priority order):
///   1. **In-memory cache** (`eventCache`) — authoritative for the current session.
///      Phase changes, book selection, and location edits all update the same
///      `EKEvent` object without ever hitting the EventKit store for a lookup.
///   2. **Firestore** (`users/{uid}.calendarEventIds`) — survives reinstalls,
///      TestFlight, and OS storage pressure clearing UserDefaults.
///   3. **UserDefaults** — legacy fallback for sessions where uid is unavailable
///      or the Firestore read fails. Also written alongside Firestore for
///      zero-latency lookups on the next cold start before Firestore responds.
actor CalendarService {

    static let shared = CalendarService()

    private let store = EKEventStore()

    /// Keyed by monthId ("2026-03"). Holds the live EKEvent for this session.
    private var eventCache: [String: EKEvent] = [:]

    private init() {}

    // MARK: - Public API

    /// Creates or updates the calendar event for the given month.
    /// Silently does nothing if `eventDate` is nil or the user denies access.
    func syncEvent(for month: ClubMonth, uid: String) async {
        guard let startDate = month.eventDate else {
            // Event date was removed — delete whatever we had
            await removeEvent(for: resolvedMonthId(for: month), uid: uid)
            return
        }

        guard await requestWriteAccess() else { return }

        let monthId = resolvedMonthId(for: month)

        // ── Locate existing event ─────────────────────────────────────────────
        // Priority: in-memory cache → Firestore → UserDefaults
        //           → EventKit search (with duplicate cleanup) → create new

        var event: EKEvent? = eventCache[monthId]

        // 2. Firestore-stored identifier (survives reinstalls)
        var firestoreId: String? = nil
        if event == nil {
            firestoreId = await fetchFirestoreEventId(uid: uid, monthId: monthId)
            if let storedId = firestoreId {
                event = store.event(withIdentifier: storedId)
                if let found = event {
                    eventCache[monthId] = found
                }
            }
        }

        // 3. UserDefaults fallback (legacy / offline)
        if event == nil {
            if let storedId = UserDefaults.standard.string(forKey: calendarKey(for: monthId)) {
                event = store.event(withIdentifier: storedId)
                if let found = event {
                    eventCache[monthId] = found
                }
            }
        }

        // 4. EventKit month-wide search — finds event even if every identifier
        //    store was wiped. Also cleans up duplicates created in the past.
        if event == nil {
            if let found = searchAndCleanupBAAMFEvents(year: month.year,
                                                       month: month.month,
                                                       preferredId: firestoreId) {
                event = found
                eventCache[monthId] = found
                // Re-anchor all stores so future lookups skip the search
                persistIdentifier(found.eventIdentifier, uid: uid, monthId: monthId)
            }
        }

        // 5. Nothing found — create a fresh event
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
        // Ownership brand — lets us distinguish BAAMF events from any user event
        // that happens to share the "BAAMF —" title prefix.
        event.url       = URL(string: "baamf://managed/\(monthId)")

        // ── Persist ───────────────────────────────────────────────────────────
        do {
            try store.save(event, span: .thisEvent)
            eventCache[monthId] = event
            persistIdentifier(event.eventIdentifier, uid: uid, monthId: monthId)
        } catch {
            print("CalendarService: save failed – \(error.localizedDescription)")
        }
    }

    /// Removes the calendar event for a month (called when the event date is cleared).
    func removeEvent(for monthId: String, uid: String) async {
        let existing: EKEvent? = eventCache[monthId] ?? {
            // Try Firestore id first (synchronous path not available, fall through)
            if let storedId = UserDefaults.standard.string(forKey: calendarKey(for: monthId)) {
                return store.event(withIdentifier: storedId)
            }
            return nil
        }()

        if let existing {
            try? store.remove(existing, span: .thisEvent)
        }

        eventCache.removeValue(forKey: monthId)
        UserDefaults.standard.removeObject(forKey: calendarKey(for: monthId))
        deleteFirestoreEventId(uid: uid, monthId: monthId)
    }

    // MARK: - Private helpers

    /// Searches the entire calendar month in EventKit for events whose title
    /// starts with "BAAMF —".
    ///
    /// If **multiple** matches are found (duplicates from past sessions), all
    /// but the keeper are deleted from EventKit. The keeper is chosen by
    /// preferring the event whose identifier matches `preferredId` (the
    /// Firestore-stored one), falling back to the first result.
    ///
    /// Searching the full month (rather than ±1 day around the event date)
    /// means we still find the existing event even if the host changed the
    /// event date since the identifier was last persisted.
    private func searchAndCleanupBAAMFEvents(year: Int,
                                              month: Int,
                                              preferredId: String? = nil) -> EKEvent? {
        let cal = Calendar.current
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let monthStart = cal.date(from: comps),
              let monthEnd   = cal.date(byAdding: .month, value: 1, to: monthStart)
        else { return nil }

        let predicate = store.predicateForEvents(withStart: monthStart,
                                                 end: monthEnd,
                                                 calendars: nil)
        let matches = store.events(matching: predicate)
            .filter { ($0.title ?? "").hasPrefix("BAAMF —") && $0.url?.scheme == "baamf" }

        guard !matches.isEmpty else { return nil }
        guard matches.count > 1 else { return matches[0] }

        // Duplicates detected — pick the keeper, delete the rest
        let keeper: EKEvent
        if let preferredId,
           let preferred = matches.first(where: { $0.eventIdentifier == preferredId }) {
            keeper = preferred
        } else {
            keeper = matches[0]
        }

        for duplicate in matches where duplicate.eventIdentifier != keeper.eventIdentifier {
            try? store.remove(duplicate, span: .thisEvent)
        }

        return keeper
    }

    // MARK: - Identifier persistence helpers

    /// Writes the event identifier to all three stores atomically.
    private func persistIdentifier(_ identifier: String, uid: String, monthId: String) {
        // In-memory (already done by callers that set eventCache, but harmless)
        UserDefaults.standard.set(identifier, forKey: calendarKey(for: monthId))
        saveFirestoreEventId(identifier, uid: uid, monthId: monthId)
    }

    private func calendarKey(for monthId: String) -> String {
        "baamf-calendarEvent-\(monthId)"
    }

    private func resolvedMonthId(for month: ClubMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }

    // MARK: - Firestore read / write

    private func fetchFirestoreEventId(uid: String, monthId: String) async -> String? {
        guard !uid.isEmpty else { return nil }
        let ref = Firestore.firestore()
            .collection(K.Firestore.users)
            .document(uid)
        guard let snapshot = try? await ref.getDocument(),
              snapshot.exists
        else { return nil }
        let ids = snapshot.data()?["calendarEventIds"] as? [String: String]
        return ids?[monthId]
    }

    private func saveFirestoreEventId(_ identifier: String, uid: String, monthId: String) {
        guard !uid.isEmpty else { return }
        Firestore.firestore()
            .collection(K.Firestore.users)
            .document(uid)
            .updateData(["calendarEventIds.\(monthId)": identifier]) { error in
                if let error {
                    print("CalendarService: Firestore write failed – \(error.localizedDescription)")
                }
            }
    }

    private func deleteFirestoreEventId(uid: String, monthId: String) {
        guard !uid.isEmpty else { return }
        Firestore.firestore()
            .collection(K.Firestore.users)
            .document(uid)
            .updateData(["calendarEventIds.\(monthId)": FieldValue.delete()]) { error in
                if let error {
                    print("CalendarService: Firestore delete failed – \(error.localizedDescription)")
                }
            }
    }

    // MARK: - Calendar permission

    private func requestWriteAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            // Full access is required — write-only blocks store.event(withIdentifier:)
            // and store.events(matching:), making duplicate detection impossible.
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
