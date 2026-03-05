import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class VetoViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = true
    @Published var isActing = false
    @Published var errorMessage: String?
    @Published var advancedSuccessfully = false

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

    // MARK: - Derived state

    var eligibleBooks: [Book] { books.filter { !$0.isRemovedByVeto } }
    var removedBooks: [Book]  { books.filter {  $0.isRemovedByVeto } }

    func hasHardPassed(book: Book, userId: String) -> Bool {
        book.vetoType2Voters.contains(userId)
    }

    func hardPassThreshold(memberCount: Int) -> Int {
        max(1, Int(ceil(Double(memberCount) * K.Veto.type2ThresholdFraction)))
    }

    // MARK: - Replacement eligibility

    /// The user's book that was removed by a "Read It" veto, if any.
    /// Hard Pass threshold removals are excluded — only Read It triggers replacement eligibility.
    func readItVetoedBook(for userId: String) -> Book? {
        books.first { $0.submitterId == userId && $0.isRemovedByVeto && !$0.vetoType2Penalty }
    }

    /// Whether the user can submit a replacement book during the veto window.
    func canResubmit(userId: String, month: ClubMonth) -> Bool {
        guard readItVetoedBook(for: userId) != nil else { return false }
        switch month.submissionMode {
        case .open, .theme:
            // Can resubmit if their only submission was removed
            return !eligibleBooks.contains { $0.submitterId == userId }
        case .pick4:
            // Host can add another to bring the count back up to 4
            return eligibleBooks.count < 4
        }
    }

    // MARK: - Read It Veto ("I've already read this")
    // Immediately removes the book. No charge cost. Any member can use on any book.

    func castReadItVeto(bookId: String, monthId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["isRemovedByVeto": true])
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Hard Pass Veto ("I don't want to read this")
    // Uses a Firestore transaction to atomically:
    //   1. Add userId to vetoType2Voters
    //   2. Check if the threshold is met → remove book and flag penalty
    //   3. Record a VetoCharge on the member document
    // Any member can Hard Pass any book, including their own.

    func castHardPassVeto(bookId: String,
                          monthId: String,
                          userId: String,
                          memberCount: Int) async {
        isActing = true
        errorMessage = nil

        let bookRef   = db.bookRef(monthId: monthId, bookId: bookId)
        let memberRef = db.userRef(uid: userId)
        let threshold = hardPassThreshold(memberCount: memberCount)

        do {
            _ = try await db.db.runTransaction { transaction, errorPointer in
                // Read current book state
                let bookSnap: DocumentSnapshot
                do { bookSnap = try transaction.getDocument(bookRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                var voters = bookSnap.data()?["vetoType2Voters"] as? [String] ?? []
                guard !voters.contains(userId) else { return nil }  // idempotent
                voters.append(userId)

                let hitThreshold = voters.count >= threshold

                var bookUpdates: [String: Any] = ["vetoType2Voters": voters]
                if hitThreshold {
                    bookUpdates["isRemovedByVeto"]    = true
                    bookUpdates["vetoType2Penalty"]   = true
                }
                transaction.updateData(bookUpdates, forDocument: bookRef)

                // Read current member charges and append a new one
                let memberSnap: DocumentSnapshot
                do { memberSnap = try transaction.getDocument(memberRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                var charges = memberSnap.data()?["vetoCharges"] as? [[String: Any]] ?? []
                charges.append(["usedAt": Timestamp(date: Date())])
                transaction.updateData(["vetoCharges": charges], forDocument: memberRef)

                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Advance to Voting Round 1

    func advanceToVoting(monthId: String) async {
        isActing = true
        errorMessage = nil
        do {
            try await db.monthRef(monthId: monthId)
                .updateData(["status": MonthStatus.votingR1.rawValue])
            advancedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }
}
