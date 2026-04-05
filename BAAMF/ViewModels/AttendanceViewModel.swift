import Foundation
import Combine
import FirebaseFirestore

/// Manages RSVP attendance for a single month.
/// Listens to `months/{monthId}/attendance` in real-time.
@MainActor
final class AttendanceViewModel: ObservableObject {

    @Published private(set) var records: [AttendanceRecord] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private let monthId: String
    private let db = FirestoreService.shared
    private var listener: ListenerRegistration?

    init(monthId: String) {
        self.monthId = monthId
    }

    // MARK: - Lifecycle

    func start() {
        isLoading = true
        listener = db.attendanceRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.records = snapshot?.documents
                        .compactMap { try? $0.data(as: AttendanceRecord.self) } ?? []
                }
            }
    }

    func stop() { listener?.remove() }
    deinit { listener?.remove() }

    // MARK: - Derived state

    /// The current user's yes/no status, or nil if they haven't responded.
    /// Does not distinguish maybe — use `currentUserIsMaybe` for that.
    func currentUserStatus(uid: String) -> Bool? {
        guard let record = records.first(where: { $0.id == uid }) else { return nil }
        if record.isMaybe == true { return nil }  // maybes aren't a firm yes/no
        return record.attending
    }

    /// True when the user has an active "maybe" response.
    func currentUserIsMaybe(uid: String) -> Bool {
        records.first { $0.id == uid }?.isMaybe == true
    }

    /// Confirmed attending (excluding maybes).
    var attendingCount: Int    { records.filter { $0.attending && $0.isMaybe != true }.count }
    /// Confirmed not attending (excluding maybes).
    var notAttendingCount: Int { records.filter { !$0.attending && $0.isMaybe != true }.count }
    var maybeCount: Int        { records.filter { $0.isMaybe == true }.count }

    // MARK: - Write

    func setAttendance(attending: Bool, uid: String) async {
        let data: [String: Any] = [
            "attending":  attending,
            "isMaybe":    false,
            "updatedAt":  Timestamp(date: Date())
        ]
        do {
            try await db.attendanceDocRef(monthId: monthId, uid: uid).setData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMaybe(uid: String) async {
        let data: [String: Any] = [
            "attending":  false,
            "isMaybe":    true,
            "updatedAt":  Timestamp(date: Date())
        ]
        do {
            try await db.attendanceDocRef(monthId: monthId, uid: uid).setData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes a member's attendance record entirely (used by admins to clear a selection).
    func clearAttendance(uid: String) async {
        do {
            try await db.attendanceDocRef(monthId: monthId, uid: uid).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Roll call

    /// Writes a roll call document to Firestore. A Cloud Function listens to this
    /// collection and sends push notifications to each target uid.
    func sendRollCall(sentBy: String, targetUids: [String]) async {
        guard !targetUids.isEmpty else { return }
        let data: [String: Any] = [
            "sentAt":     Timestamp(date: Date()),
            "sentBy":     sentBy,
            "targetUids": targetUids
        ]
        do {
            try await db.rollCallsRef(monthId: monthId).addDocument(data: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
