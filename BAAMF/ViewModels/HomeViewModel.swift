import Foundation
import Combine
import FirebaseFirestore

/// Drives the Home tab. Listens in real-time to the current month document
/// and its books subcollection. This ViewModel is the source of truth for
/// whatever phase of the monthly lifecycle the club is in.
@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var currentMonth: ClubMonth?
    @Published private(set) var books: [Book] = []
    @Published private(set) var allMembers: [Member] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let firestoreService = FirestoreService.shared
    private var monthListener: ListenerRegistration?
    private var booksListener: ListenerRegistration?

    // MARK: - Lifecycle

    func start(currentUserId: String) {
        let monthId = ClubMonth.currentMonthId()
        isLoading = true
        startMonthListener(monthId: monthId)
        Task { await loadAllMembers() }
    }

    func stop() {
        monthListener?.remove()
        booksListener?.remove()
    }

    deinit {
        monthListener?.remove()
        booksListener?.remove()
    }

    // MARK: - Derived state helpers

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

    private func startMonthListener(monthId: String) {
        monthListener = firestoreService.monthRef(monthId: monthId)
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
                }
            }
    }

    private func startBooksListener(monthId: String) {
        guard booksListener == nil else { return }  // Don't double-subscribe
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

    private func loadAllMembers() async {
        do {
            allMembers = try await firestoreService.fetchAllMembers()
                .sorted { $0.name < $1.name }
        } catch {
            // Non-fatal — members list is supplemental
        }
    }

    // MARK: - Member name lookup

    func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    // MARK: - Veto replacement eligibility

    /// True when the current user had a book removed by a "Read It" veto
    /// and can still submit a replacement before the veto window closes.
    ///
    /// - Open/Theme: user's only submission was Read It'd and they have no eligible book.
    /// - Pick-4: host had a book Read It'd and the eligible count is below 4.
    func userNeedsReplacement(userId: String) -> Bool {
        guard let month = currentMonth, month.status == .vetoes else { return false }

        let userBooks = books.filter { $0.submitterId == userId }
        // Must have had at least one Read It (not Hard Pass threshold) removal
        let wasReadItVetoed = userBooks.contains { $0.isRemovedByVeto && !$0.vetoType2Penalty }
        guard wasReadItVetoed else { return false }

        switch month.submissionMode {
        case .open, .theme:
            // User's submission was removed and they have no replacement yet
            return !userBooks.contains { !$0.isRemovedByVeto }
        case .pick4:
            // Host had a book removed and can fill the slot back up to 4
            return eligibleBooks.count < 4
        }
    }
}
