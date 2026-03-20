import Foundation
import Combine
import FirebaseFirestore

/// Drives the admin "Edit Scores" sheet for a completed (or historical) month.
///
/// Loads existing score documents, lets admins add/update/remove scores for any
/// member, then batch-writes the changes and recalculates `groupAvgScore` on
/// the month document.
@MainActor
final class EditCompletedMonthViewModel: ObservableObject {

    // MARK: - Properties

    let month: ClubMonth

    @Published private(set) var allMembers: [Member] = []
    @Published var memberScores: [String: Double] = [:]
    @Published var participating: Set<String> = []
    /// Empty string means "unknown / not recorded".
    @Published var selectedSubmitterId: String = ""

    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false

    private let db = FirestoreService.shared

    // MARK: - Init

    init(month: ClubMonth) {
        self.month = month
    }

    // MARK: - Load

    func start() {
        Task {
            do {
                async let members = db.fetchAllMembers()
                async let scores  = fetchScores()

                let (loadedMembers, loadedScores) = try await (members, scores)

                allMembers = loadedMembers.filter { !$0.isObserver }.sorted { $0.name < $1.name }

                // Seed submitter from the month document
                selectedSubmitterId = month.selectedBookSubmitterId ?? ""

                // Seed current values from existing score docs
                for score in loadedScores {
                    participating.insert(score.scorerId)
                    memberScores[score.scorerId] = score.score
                }

                // Members not yet in scores default to 4.0 but are NOT toggled on —
                // admin must explicitly opt them in.
                for member in allMembers {
                    guard let id = member.id else { continue }
                    if memberScores[id] == nil {
                        memberScores[id] = 4.0
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Participation toggle

    func toggleParticipation(for userId: String) {
        if participating.contains(userId) {
            participating.remove(userId)
        } else {
            participating.insert(userId)
        }
    }

    // MARK: - Save

    func save() {
        guard let monthId = month.id else { return }
        isSaving = true

        Task {
            do {
                let batch = db.db.batch()

                // Fetch current score doc IDs so we can delete removed ones
                let existingScoreDocs = try await db.scoresRef(monthId: monthId).getDocuments()
                let existingIds = Set(existingScoreDocs.documents.map { $0.documentID })

                // Upsert score docs for participating members
                let now = Timestamp(date: Date())
                for userId in participating {
                    let score = memberScores[userId] ?? 4.0
                    let data: [String: Any] = [
                        "bookId":    "",
                        "scorerId":  userId,
                        "score":     score,
                        "updatedAt": now
                    ]
                    batch.setData(data, forDocument: db.scoresRef(monthId: monthId).document(userId))
                }

                // Delete score docs for members no longer participating
                for docId in existingIds where !participating.contains(docId) {
                    batch.deleteDocument(db.scoresRef(monthId: monthId).document(docId))
                }

                // Recalculate groupAvgScore
                let participatingScores = memberScores.filter { participating.contains($0.key) }
                let groupAvg: Double? = participatingScores.isEmpty ? nil : {
                    let total = participatingScores.values.reduce(0, +)
                    return total / Double(participatingScores.count)
                }()

                var monthUpdate: [String: Any] = [
                    "groupAvgScore": groupAvg as Any
                ]
                if selectedSubmitterId.isEmpty {
                    monthUpdate["selectedBookSubmitterId"] = FieldValue.delete()
                } else {
                    monthUpdate["selectedBookSubmitterId"] = selectedSubmitterId
                }
                batch.updateData(monthUpdate, forDocument: db.monthRef(monthId: monthId))

                try await batch.commit()
                NotificationCenter.default.post(name: .scoresDidUpdate, object: nil)
                didSave = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func fetchScores() async throws -> [BookScore] {
        guard let monthId = month.id else { return [] }
        let snapshot = try await db.scoresRef(monthId: monthId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: BookScore.self) }
    }
}
