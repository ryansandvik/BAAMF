import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class VotingViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = true
    @Published var isActing = false
    @Published var errorMessage: String?

    private let db = FirestoreService.shared
    private var listener: ListenerRegistration?

    // MARK: - Lifecycle

    func start(monthId: String) {
        isLoading = true
        listener = db.booksRef(monthId: monthId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.books = snapshot?.documents
                        .compactMap { try? $0.data(as: Book.self) } ?? []
                }
            }
    }

    func stop() { listener?.remove() }
    deinit { listener?.remove() }

    // MARK: - Round 1 derived state

    /// Eligible books in stable alphabetical order.
    /// Sorting by vote count was removed because it caused cards to jump
    /// as votes were cast, which was confusing for users.
    var r1Books: [Book] {
        books
            .filter { $0.isEligibleForR1 }
            .sorted { $0.title < $1.title }
    }

    /// How many R1 votes the user has cast so far.
    func r1VotesCast(userId: String) -> Int {
        r1Books.filter { $0.votingR1Voters.contains(userId) }.count
    }

    func hasVotedR1(book: Book, userId: String) -> Bool {
        book.votingR1Voters.contains(userId)
    }

    // MARK: - Round 2 derived state

    /// Books that advanced from R1, in stable alphabetical order.
    /// Sorting by live R2 vote count was removed to prevent cards from jumping.
    var r2Books: [Book] {
        books
            .filter { $0.isEligibleForR2 }
            .sorted { $0.title < $1.title }
    }

    func r2VotesCast(userId: String) -> Int {
        r2Books.filter { $0.votingR2Voters.contains(userId) }.count
    }

    func hasVotedR2(book: Book, userId: String) -> Bool {
        book.votingR2Voters.contains(userId)
    }

    // MARK: - Cast R1 vote
    // Uses arrayUnion for idempotency — won't add duplicate voter IDs.

    func castR1Vote(bookId: String, monthId: String, userId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["votingR1Voters": FieldValue.arrayUnion([userId])])
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Cast R2 vote

    func castR2Vote(bookId: String, monthId: String, userId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["votingR2Voters": FieldValue.arrayUnion([userId])])
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Remove votes (user changes their mind before round closes)

    func removeR1Vote(bookId: String, monthId: String, userId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["votingR1Voters": FieldValue.arrayRemove([userId])])
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    func removeR2Vote(bookId: String, monthId: String, userId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["votingR2Voters": FieldValue.arrayRemove([userId])])
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }
}
