import Foundation
import Combine
import FirebaseFirestore

/// One entry in the user's personal favourites list.
struct FavoriteEntry: Identifiable {
    var id: String { month.id ?? "\(month.year)-\(month.month)" }
    let month: ClubMonth
    let personalScore: Double
}

/// Loads the logged-in user's personal scores for all complete months,
/// groups them by year, and presents the selected year's books sorted
/// by personal score descending.
@MainActor
final class FavoriteBooksViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedYear: Int
    @Published private(set) var favorites: [FavoriteEntry] = []
    @Published private(set) var availableYears: [Int] = []
    @Published private(set) var allMembers: [Member] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = FirestoreService.shared
    private let userId: String
    /// All complete months fetched once; score fan-out reuses this.
    private var completeMonths: [ClubMonth] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(userId: String) {
        self.userId = userId
        self.selectedYear = Calendar.current.component(.year, from: Date())

        // Re-run the score fan-out whenever an admin edits scores
        NotificationCenter.default
            .publisher(for: .scoresDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.yearChanged() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                // Fetch all complete months once
                let snapshot = try await db.monthsRef()
                    .whereField("status", isEqualTo: MonthStatus.complete.rawValue)
                    .getDocuments()
                completeMonths = snapshot.documents
                    .compactMap { try? $0.data(as: ClubMonth.self) }
                    .sorted { ($0.year, $0.month) > ($1.year, $1.month) }

                // Fetch all members for HistoryDetailView navigation (exclude observers)
                allMembers = ((try? await db.fetchAllMembers()) ?? [])
                    .filter { !$0.isObserver && !$0.isVirtual }

                // Derive available years
                availableYears = Array(Set(completeMonths.map { $0.year })).sorted(by: >)

                // Default to most recent year with data
                if let first = availableYears.first, !availableYears.contains(selectedYear) {
                    selectedYear = first
                }

                try await loadFavoritesForSelectedYear()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Called whenever `selectedYear` changes.
    func yearChanged() {
        Task {
            isLoading = true
            do {
                try await loadFavoritesForSelectedYear()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Private helpers

    private func loadFavoritesForSelectedYear() async throws {
        let monthsForYear = completeMonths.filter { $0.year == selectedYear }
        guard !monthsForYear.isEmpty else {
            favorites = []
            return
        }

        // Fan-out: fetch the user's score doc for each month in parallel
        let entries: [FavoriteEntry] = try await withThrowingTaskGroup(of: FavoriteEntry?.self) { group in
            for month in monthsForYear {
                guard let monthId = month.id else { continue }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let scoreDoc = try? await self.db.scoresRef(monthId: monthId)
                        .document(self.userId)
                        .getDocument()
                    guard
                        let data = scoreDoc?.data(),
                        let score = data["score"] as? Double
                    else { return nil }
                    return FavoriteEntry(month: month, personalScore: score)
                }
            }

            var results: [FavoriteEntry] = []
            for try await entry in group {
                if let entry { results.append(entry) }
            }
            return results
        }

        favorites = entries.sorted { $0.personalScore > $1.personalScore }
    }
}
