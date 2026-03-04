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

    /// Books visible for the current round (excludes Type 1-vetoed books).
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
}
