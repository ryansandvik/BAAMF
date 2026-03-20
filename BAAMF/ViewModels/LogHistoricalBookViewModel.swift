import Foundation
import Combine
import FirebaseFirestore

/// Drives the "Log Historical Book" admin sheet.
///
/// Admins use this to back-fill a club month that predates the app.
/// The ViewModel:
///   1. Lets the admin pick a year + month and verifies no document exists yet.
///   2. Lets them search for and select the book via Google Books.
///   3. Lets them enter each member's score (or mark them as not participating).
///   4. Batch-writes the `months/{monthId}` doc and `months/{monthId}/scores/{userId}` docs.
@MainActor
final class LogHistoricalBookViewModel: ObservableObject {

    // MARK: - Published form state

    @Published var selectedYear: Int
    @Published var selectedMonth: Int = 1

    @Published var selectedHostId: String = ""
    /// Empty string means "unknown / not recorded".
    @Published var selectedSubmitterId: String = ""

    // Book
    @Published var bookTitle: String = ""
    @Published var bookAuthor: String = ""
    @Published var bookCoverUrl: String = ""

    // Per-member score entry
    /// userId → score (1.0 – 7.0)
    @Published var memberScores: [String: Double] = [:]
    /// userIds of members who participated (and therefore have a score)
    @Published var participating: Set<String> = []

    // MARK: - Published status

    @Published private(set) var allMembers: [Member] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var monthAlreadyExists = false
    @Published var errorMessage: String?
    @Published var didSave = false

    // MARK: - Constants

    let availableYears: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(2015...currentYear).reversed()
    }()

    let monthNames: [String] = Calendar.current.monthSymbols

    // MARK: - Private

    private let db = FirestoreService.shared
    private var existenceCheckTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let cal = Calendar.current
        let now = Date()
        self.selectedYear  = cal.component(.year,  from: now)
        self.selectedMonth = cal.component(.month, from: now)
    }

    // MARK: - Lifecycle

    func start() {
        isLoading = true
        Task {
            do {
                allMembers = try await db.fetchAllMembers().filter { !$0.isObserver }.sorted { $0.name < $1.name }
                // Default all members to participating at score 4.0
                for member in allMembers {
                    guard let id = member.id else { continue }
                    participating.insert(id)
                    memberScores[id] = 4.0
                }
                // Default host to first member
                if selectedHostId.isEmpty, let first = allMembers.first?.id {
                    selectedHostId = first
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            checkMonthExists()
        }
    }

    // MARK: - Month existence check

    /// Called whenever year or month changes. Debounced via task cancellation.
    func checkMonthExists() {
        existenceCheckTask?.cancel()
        existenceCheckTask = Task {
            do {
                let monthId = ClubMonth.monthId(year: selectedYear, month: selectedMonth)
                let snapshot = try await db.monthRef(monthId: monthId).getDocument()
                guard !Task.isCancelled else { return }
                monthAlreadyExists = snapshot.exists
            } catch {
                guard !Task.isCancelled else { return }
                monthAlreadyExists = false
            }
        }
    }

    // MARK: - Book selection

    func applyBook(_ item: GoogleBooksItem) {
        bookTitle    = item.title
        bookAuthor   = item.author
        bookCoverUrl = item.coverUrl ?? ""
    }

    // MARK: - Participation toggle

    func toggleParticipation(for userId: String) {
        if participating.contains(userId) {
            participating.remove(userId)
        } else {
            participating.insert(userId)
            if memberScores[userId] == nil {
                memberScores[userId] = 4.0
            }
        }
    }

    // MARK: - Validation

    var canSave: Bool {
        !bookTitle.isEmpty
            && !selectedHostId.isEmpty
            && !monthAlreadyExists
            && !participating.isEmpty
    }

    // MARK: - Save

    func save() {
        guard canSave else { return }
        isSaving = true

        Task {
            do {
                let monthId = ClubMonth.monthId(year: selectedYear, month: selectedMonth)
                let batch   = db.db.batch()

                // ── Month document ────────────────────────────────────────────
                let participatingScores = memberScores.filter { participating.contains($0.key) }
                let groupAvg: Double? = participatingScores.isEmpty ? nil : {
                    let total = participatingScores.values.reduce(0, +)
                    return total / Double(participatingScores.count)
                }()

                // Build month doc — omit cover key entirely when empty.
                // FieldValue.delete() is only valid in updateData, not setData.
                var monthData: [String: Any] = [
                    "year":               selectedYear,
                    "month":              selectedMonth,
                    "hostId":             selectedHostId,
                    "submissionMode":     SubmissionMode.open.rawValue,
                    "status":             MonthStatus.complete.rawValue,
                    "isHistorical":       true,
                    "selectedBookTitle":  bookTitle,
                    "selectedBookAuthor": bookAuthor,
                    "groupAvgScore":      groupAvg as Any
                ]
                if !bookCoverUrl.isEmpty {
                    monthData["selectedBookCoverUrl"] = bookCoverUrl
                }
                if !selectedSubmitterId.isEmpty {
                    monthData["selectedBookSubmitterId"] = selectedSubmitterId
                }
                batch.setData(monthData, forDocument: db.monthRef(monthId: monthId))

                // ── Score documents ───────────────────────────────────────────
                let now = Timestamp(date: Date())
                for userId in participating {
                    let score = memberScores[userId] ?? 4.0
                    let scoreData: [String: Any] = [
                        "bookId":    "",          // No separate Book document for historical entries
                        "scorerId":  userId,
                        "score":     score,
                        "updatedAt": now
                    ]
                    batch.setData(scoreData,
                                  forDocument: db.scoresRef(monthId: monthId).document(userId))
                }

                try await batch.commit()
                didSave = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
