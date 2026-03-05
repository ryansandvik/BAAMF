import Foundation
import Combine

@MainActor
final class BookSearchViewModel: ObservableObject {

    @Published var query = ""
    @Published private(set) var results: [GoogleBooksItem] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var errorMessage: String?

    private let service = GoogleBooksService.shared
    private var searchTask: Task<Void, Never>?

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        hasSearched = false

        searchTask = Task {
            do {
                let items = try await service.search(query: trimmed)
                guard !Task.isCancelled else { return }
                results = items
                hasSearched = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                results = []
                hasSearched = true
            }
            isSearching = false
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        results = []
        hasSearched = false
        errorMessage = nil
    }
}
