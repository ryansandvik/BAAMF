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

    /// The current user's attendance status, or nil if they haven't responded.
    func currentUserStatus(uid: String) -> Bool? {
        records.first { $0.id == uid }?.attending
    }

    var attendingCount: Int { records.filter { $0.attending }.count }
    var notAttendingCount: Int { records.filter { !$0.attending }.count }

    // MARK: - Write

    func setAttendance(attending: Bool, uid: String) async {
        let data: [String: Any] = [
            "attending":  attending,
            "updatedAt":  Timestamp(date: Date())
        ]
        do {
            try await db.attendanceDocRef(monthId: monthId, uid: uid).setData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
