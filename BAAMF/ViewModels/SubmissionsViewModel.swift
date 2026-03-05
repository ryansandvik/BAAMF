import Foundation
import Combine
import FirebaseFirestore

/// Encodable struct used when writing a new book document to Firestore.
/// Keeps writes clean without a raw dictionary.
private struct BookSubmission: Encodable {
    let title: String
    let author: String
    let description: String
    let pitchOverride: String
    let submitterId: String
    let googleBooksId: String
    let googleRating: Double?
    let pageCount: Int?
    let coverUrl: String?
    let isRemovedByVeto: Bool
    let vetoType2Voters: [String]
    let vetoType2Penalty: Bool
    let netVotesR1: Int
    let netVotesR2: Int
    let advancedToR2: Bool
}

@MainActor
final class SubmissionsViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = true
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var submittedSuccessfully = false

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

    /// True if the user has already submitted a (non-vetoed) book this month.
    func hasSubmitted(userId: String) -> Bool {
        books.contains { $0.submitterId == userId && !$0.isRemovedByVeto }
    }

    /// Whether the current user is allowed to submit in this month's mode.
    func canSubmit(userId: String, month: ClubMonth, isHost: Bool) -> Bool {
        guard month.status == .submissions else { return false }
        switch month.submissionMode {
        case .open, .theme:
            return !hasSubmitted(userId: userId)
        case .pick4:
            // Only the host can submit, and only up to 4 books
            return isHost && eligibleBooks.count < 4
        }
    }

    var eligibleBooks: [Book] {
        books.filter { !$0.isRemovedByVeto }
    }

    // MARK: - Edit / Delete / Swap

    /// Updates only the pitch on an existing book document.
    func updateBookPitch(bookId: String, monthId: String, pitch: String) async {
        let trimmed = pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId)
                .updateData(["pitchOverride": trimmed])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a book document. The real-time listener in SubmissionsView will
    /// reflect the removal automatically.
    func deleteBook(bookId: String, monthId: String) async {
        do {
            try await db.bookRef(monthId: monthId, bookId: bookId).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces the book metadata on an existing document (keeps the same doc ID,
    /// submitter, and vote/veto fields). Used for the "Swap Book" flow.
    func swapBook(existingBookId: String,
                  monthId: String,
                  newBook: GoogleBooksItem,
                  pitch: String) async {
        isSubmitting = true
        errorMessage = nil

        var data: [String: Any] = [
            "title":         newBook.title,
            "author":        newBook.author,
            "description":   newBook.description,
            "pitchOverride": pitch.trimmingCharacters(in: .whitespacesAndNewlines),
            "googleBooksId": newBook.id
        ]

        if let rating = newBook.rating   { data["googleRating"] = rating }
        else                             { data["googleRating"] = FieldValue.delete() }
        if let pages = newBook.pageCount { data["pageCount"] = pages }
        else                             { data["pageCount"] = FieldValue.delete() }
        if let cover = newBook.coverUrl  { data["coverUrl"] = cover }
        else                             { data["coverUrl"] = FieldValue.delete() }

        do {
            try await db.bookRef(monthId: monthId, bookId: existingBookId).updateData(data)
            submittedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    // MARK: - Submit

    func submitBook(_ googleBook: GoogleBooksItem,
                    pitch: String,
                    monthId: String,
                    submitterId: String) async {
        isSubmitting = true
        errorMessage = nil

        let submission = BookSubmission(
            title:           googleBook.title,
            author:          googleBook.author,
            description:     googleBook.description,
            pitchOverride:   pitch.trimmingCharacters(in: .whitespacesAndNewlines),
            submitterId:     submitterId,
            googleBooksId:   googleBook.id,
            googleRating:    googleBook.rating,
            pageCount:       googleBook.pageCount,
            coverUrl:        googleBook.coverUrl,
            isRemovedByVeto: false,
            vetoType2Voters: [],
            vetoType2Penalty: false,
            netVotesR1:      0,
            netVotesR2:      0,
            advancedToR2:    false
        )

        do {
            try db.booksRef(monthId: monthId).addDocument(from: submission)
            submittedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
