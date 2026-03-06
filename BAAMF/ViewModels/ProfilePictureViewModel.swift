import SwiftUI
import Combine
import PhotosUI
import FirebaseStorage
import FirebaseFirestore

/// Handles profile picture selection, compression, upload to Firebase Storage,
/// and persisting the download URL to Firestore.
@MainActor
final class ProfilePictureViewModel: ObservableObject {

    @Published var selectedItem: PhotosPickerItem? {
        didSet { Task { await processSelection() } }
    }

    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let uid: String
    private let firestoreService = FirestoreService.shared

    init(uid: String) {
        self.uid = uid
    }

    // MARK: - Process PhotosPicker selection

    private func processSelection() async {
        guard let item = selectedItem else { return }
        isUploading = true
        errorMessage = nil

        do {
            // Load the raw data from the picker item
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw UploadError.loadFailed
            }

            // Compress to JPEG (max 800×800, quality 0.7) — keeps storage costs low
            guard let compressed = compressImage(data: data, maxDimension: 800, quality: 0.7) else {
                throw UploadError.compressionFailed
            }

            // Upload to Firebase Storage
            let downloadURL = try await uploadToStorage(data: compressed)

            // Persist the URL to Firestore
            try await firestoreService.userRef(uid: uid)
                .updateData(["photoURL": downloadURL])

            // Post notification so AuthViewModel reloads the member profile
            NotificationCenter.default.post(name: .profileDidUpdate, object: nil)

        } catch {
            errorMessage = "Photo upload failed: \(error.localizedDescription)"
        }

        isUploading = false
        selectedItem = nil
    }

    // MARK: - Firebase Storage upload

    private func uploadToStorage(data: Data) async throws -> String {
        // Path matches storage.rules: profilePictures/{userId}/{fileName}
        let storageRef = Storage.storage()
            .reference()
            .child("profilePictures/\(uid)/profile.jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(data, metadata: metadata)
        let url = try await storageRef.downloadURL()
        return url.absoluteString
    }

    // MARK: - Image compression

    private func compressImage(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }

        let size = uiImage.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Errors

    private enum UploadError: LocalizedError {
        case loadFailed
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed:       return "Could not load the selected image."
            case .compressionFailed: return "Could not process the selected image."
            }
        }
    }
}
