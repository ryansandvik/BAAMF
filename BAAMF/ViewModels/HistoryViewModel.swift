import Foundation
import Combine
import FirebaseFirestore

/// Loads all complete months and the full member list for the History tab.
@MainActor
final class HistoryViewModel: ObservableObject {

    @Published private(set) var months: [ClubMonth] = []
    @Published private(set) var allMembers: [Member] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let db = FirestoreService.shared
    private var listener: ListenerRegistration?

    // MARK: - Lifecycle

    func start() {
        isLoading = true
        // Load all members once (they rarely change)
        Task {
            do {
                allMembers = try await db.fetchAllMembers().filter { !$0.isObserver }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Listen for complete months. Sorting is done client-side to avoid
        // requiring a composite Firestore index on (status + year + month).
        listener = db.monthsRef()
            .whereField("status", isEqualTo: MonthStatus.complete.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.months = (snapshot?.documents
                        .compactMap { try? $0.data(as: ClubMonth.self) } ?? [])
                        .sorted {
                            if $0.year != $1.year { return $0.year > $1.year }
                            return $0.month > $1.month
                        }
                }
            }
    }

    func stop() { listener?.remove() }
    deinit { listener?.remove() }

    // MARK: - Helpers

    func memberName(for userId: String) -> String {
        allMembers.first { $0.id == userId }?.name ?? "Unknown"
    }

    /// Months grouped and sorted newest-year-first. Each group's months are
    /// already sorted newest-month-first by the listener sort above.
    var monthsByYear: [(year: Int, months: [ClubMonth])] {
        let years = Set(months.map { $0.year }).sorted(by: >)
        return years.map { year in
            (year, months.filter { $0.year == year })
        }
    }
}
