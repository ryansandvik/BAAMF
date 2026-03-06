import Foundation
import Combine
import FirebaseFirestore

/// Drives the Home tab.
///
/// Listens in real-time to three Firestore month documents simultaneously:
///   • **previousMonth** — shown if it still has an active (non-complete) phase,
///     so a month that ran late doesn't silently disappear on the 1st.
///   • **currentMonth** — the primary card; always shown when it exists.
///   • **nextMonth** — shown once its document has been created (triggered
///     automatically when the current month advances to .reading).
///
/// Books are only subscribed to for the current month document since that is the
/// only card that needs dynamic book data on the home screen.
@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var previousMonth: ClubMonth?
    @Published private(set) var currentMonth: ClubMonth?
    @Published private(set) var nextMonth: ClubMonth?
    @Published private(set) var books: [Book] = []
    @Published private(set) var allMembers: [Member] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let firestoreService = FirestoreService.shared
    private var previousMonthListener: ListenerRegistration?
    private var currentMonthListener: ListenerRegistration?
    private var nextMonthListener: ListenerRegistration?
    private var booksListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?

    // MARK: - Lifecycle

    func start(currentUserId: String) {
        isLoading = true
        let ids = Self.adjacentMonthIds()
        startPreviousMonthListener(monthId: ids.previous)
        startCurrentMonthListener(monthId: ids.current)
        startNextMonthListener(monthId: ids.next)
        startMembersListener()
    }

    func stop() {
        previousMonthListener?.remove()
        currentMonthListener?.remove()
        nextMonthListener?.remove()
        booksListener?.remove()
        membersListener?.remove()
    }

    deinit {
        previousMonthListener?.remove()
        currentMonthListener?.remove()
        nextMonthListener?.remove()
        booksListener?.remove()
        membersListener?.remove()
    }

    // MARK: - Derived state helpers

    var hasAnyMonth: Bool {
        previousMonth != nil || currentMonth != nil || nextMonth != nil
    }

    func isCurrentUserHost(userId: String) -> Bool {
        currentMonth?.hostId == userId
    }

    func canControlStatus(userId: String, isAdmin: Bool) -> Bool {
        isAdmin || isCurrentUserHost(userId: userId)
    }

    /// Books visible for the current round (excludes Read It–vetoed books).
    var eligibleBooks: [Book] {
        books.filter { !$0.isRemovedByVeto }
    }

    /// Books that advanced to Round 2.
    var r2Books: [Book] {
        books.filter { $0.advancedToR2 && !$0.isRemovedByVeto }
    }

    // MARK: - Private listeners

    private func startPreviousMonthListener(monthId: String) {
        previousMonthListener = firestoreService.monthRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let month = try? snapshot?.data(as: ClubMonth.self)
                    // Only surface it if it's not yet complete — complete months
                    // leave home when the calendar rolls over.
                    self.previousMonth = (month?.status != .complete) ? month : nil
                    if let month { Task { await CalendarService.shared.syncEvent(for: month) } }
                }
            }
    }

    private func startCurrentMonthListener(monthId: String) {
        currentMonthListener = firestoreService.monthRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.currentMonth = try? snapshot?.data(as: ClubMonth.self)
                    if self.currentMonth != nil {
                        self.startBooksListener(monthId: monthId)
                    }
                    if let month = self.currentMonth {
                        Task { await CalendarService.shared.syncEvent(for: month) }
                    }
                }
            }
    }

    private func startNextMonthListener(monthId: String) {
        nextMonthListener = firestoreService.monthRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.nextMonth = try? snapshot?.data(as: ClubMonth.self)
                    if let month = self.nextMonth {
                        Task { await CalendarService.shared.syncEvent(for: month) }
                    }
                }
            }
    }

    private func startBooksListener(monthId: String) {
        guard booksListener == nil else { return }   // Don't double-subscribe
        booksListener = firestoreService.booksRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.books = snapshot?.documents
                        .compactMap { try? $0.data(as: Book.self) } ?? []
                }
            }
    }

    private func startMembersListener() {
        membersListener = firestoreService.usersRef()
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.allMembers = (snapshot?.documents
                        .compactMap { try? $0.data(as: Member.self) } ?? [])
                        .sorted { $0.name < $1.name }
                }
            }
    }

    // MARK: - Member name lookup

    func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    // MARK: - Veto replacement eligibility

    /// True when the current user had a book removed by a "Read It" veto
    /// and can still submit a replacement before the veto window closes.
    func userNeedsReplacement(userId: String) -> Bool {
        guard let month = currentMonth, month.status == .vetoes else { return false }

        let userBooks = books.filter { $0.submitterId == userId }
        let wasReadItVetoed = userBooks.contains { $0.isRemovedByVeto && !$0.vetoType2Penalty }
        guard wasReadItVetoed else { return false }

        switch month.submissionMode {
        case .open, .theme:
            return !userBooks.contains { !$0.isRemovedByVeto }
        case .pick4:
            return eligibleBooks.count < 4
        }
    }

    // MARK: - Helpers

    /// Computes the Firestore document IDs for the previous, current, and next
    /// calendar months, handling January ↔ December year boundaries.
    static func adjacentMonthIds() -> (previous: String, current: String, next: String) {
        let cal   = Calendar.current
        let now   = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)

        let (prevYear, prevMonth) = month == 1  ? (year - 1, 12) : (year, month - 1)
        let (nextYear, nextMonth) = month == 12 ? (year + 1, 1)  : (year, month + 1)

        return (
            ClubMonth.monthId(year: prevYear, month: prevMonth),
            ClubMonth.monthId(year: year,     month: month),
            ClubMonth.monthId(year: nextYear, month: nextMonth)
        )
    }
}
