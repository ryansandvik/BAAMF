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
