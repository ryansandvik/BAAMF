import Foundation
import Combine
import FirebaseFirestore

/// Loads and saves the app-wide phase deadline defaults from/to `settings/defaults`.
@MainActor
final class AppSettingsViewModel: ObservableObject {

    @Published var settings = AppSettings()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var savedFeedback = false

    private let db = FirestoreService.shared

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.settingsRef().getDocument()
            if snap.exists, let loaded = try? snap.data(as: AppSettings.self) {
                settings = loaded
            }
            // If doc doesn't exist yet, leave the in-memory defaults in place.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try db.settingsRef().setData(from: settings, merge: true)
            savedFeedback = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            savedFeedback = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
