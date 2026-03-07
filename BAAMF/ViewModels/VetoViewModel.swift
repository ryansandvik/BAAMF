import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class VetoViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    /// Live member list — kept in sync so charge counts update instantly after a Hard Pass.
    @Published private(set) var members: [Member] = []
    @Published var isLoading = true
    @Published var isActing = false
    @Published var errorMessage: String?
    @Published var advancedSuccessfully = false

    private let db = FirestoreService.shared
    private var booksListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?

    // MARK: - Lifecycle

    func start(monthId: String) {
        isLoading = true

        booksListener = db.booksRef(monthId: monthId)
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

        membersListener = db.usersRef()
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.members = snapshot?.documents
                        .compactMap { try? $0.data(as: Member.self) } ?? []
                }
            }
    }

    func stop() {
        booksListener?.remove()
        membersListener?.remove()
    }
    deinit {
        booksListener?.remove()
        membersListener?.remove()
    }

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
    // Removes the book immediately. No charge cost. Any member can use on any book.
    // Uses a transaction so that any Hard Pass charges spent on this book are atomically
    // refunded to the voters at the same time — they shouldn't be penalised for a book
    // that was never going to make it to voting.

    func castReadItVeto(bookId: String, monthId: String) async {
        isActing = true
        errorMessage = nil

        let bookRef  = db.bookRef(monthId: monthId, bookId: bookId)
        let firestoreDb = db

        do {
            _ = try await db.db.runTransaction { transaction, errorPointer in
                // ── ALL READS FIRST ──────────────────────────────────────────
                // Firestore transactions require every read to precede every write.

                // Read 1: book doc (to discover Hard Pass voters)
                let bookSnap: DocumentSnapshot
                do { bookSnap = try transaction.getDocument(bookRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                let hardPassVoters = bookSnap.data()?["vetoType2Voters"] as? [String] ?? []

                // Read 2…N: one member doc per Hard Pass voter
                var memberSnaps: [String: DocumentSnapshot] = [:]
                for userId in hardPassVoters {
                    let memberRef = firestoreDb.userRef(uid: userId)
                    let snap: DocumentSnapshot
                    do { snap = try transaction.getDocument(memberRef) }
                    catch let e as NSError { errorPointer?.pointee = e; return nil }
                    memberSnaps[userId] = snap
                }

                // ── ALL WRITES AFTER ─────────────────────────────────────────

                // Mark book as removed by Read It veto
                transaction.updateData(["isRemovedByVeto": true], forDocument: bookRef)

                // Refund one Hard Pass charge to every voter on this book
                for userId in hardPassVoters {
                    guard let memberSnap = memberSnaps[userId] else { continue }
                    let memberRef = firestoreDb.userRef(uid: userId)
                    var charges = memberSnap.data()?["vetoCharges"] as? [[String: Any]] ?? []
                    if !charges.isEmpty {
                        charges.removeLast()  // refund the most recently used charge
                        transaction.updateData(["vetoCharges": charges], forDocument: memberRef)
                    }
                }

                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }

    // MARK: - Hard Pass Veto ("I don't want to read this")
    // Uses a Firestore transaction to atomically:
    //   1. Add userId to vetoType2Voters
    //   2. If threshold is met → set vetoType2Penalty (book is NOT removed; it loses 2 pts in R1)
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
                // ── ALL READS FIRST ──────────────────────────────────────────

                // Read 1: book doc
                let bookSnap: DocumentSnapshot
                do { bookSnap = try transaction.getDocument(bookRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                // Read 2: member doc
                let memberSnap: DocumentSnapshot
                do { memberSnap = try transaction.getDocument(memberRef) }
                catch let e as NSError { errorPointer?.pointee = e; return nil }

                // ── ALL WRITES AFTER ─────────────────────────────────────────

                var voters = bookSnap.data()?["vetoType2Voters"] as? [String] ?? []
                guard !voters.contains(userId) else { return nil }  // idempotent
                voters.append(userId)

                var bookUpdates: [String: Any] = ["vetoType2Voters": voters]
                if voters.count >= threshold {
                    bookUpdates["vetoType2Penalty"] = true
                }
                transaction.updateData(bookUpdates, forDocument: bookRef)

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
            var update: [String: Any] = ["status": MonthStatus.votingR1.rawValue]
            // Read the default R1 deadline from AppSettings so the notification
            // and the app always show the same date.
            if let settings = try? await db.settingsRef().getDocument().data(as: AppSettings.self),
               let deadline = settings.defaultDeadline(for: .votingR1) {
                update["votingR1Deadline"] = Timestamp(date: deadline)
            }
            try await db.monthRef(monthId: monthId).updateData(update)
            advancedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isActing = false
    }
}
