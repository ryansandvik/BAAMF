import Foundation

// MARK: - API response envelope

struct GoogleBooksSearchResponse: Codable {
    let items: [GoogleBooksItem]?
}

// MARK: - Individual book result

struct GoogleBooksItem: Codable, Identifiable {
    let id: String
    let volumeInfo: VolumeInfo

    struct VolumeInfo: Codable {
        let title: String?
        let authors: [String]?
        let description: String?
        let pageCount: Int?
        let averageRating: Double?
        let imageLinks: ImageLinks?

        struct ImageLinks: Codable {
            let thumbnail: String?
            let smallThumbnail: String?
        }
    }

    // MARK: - Convenience accessors

    var title: String       { volumeInfo.title ?? "Unknown Title" }
    var author: String      { volumeInfo.authors?.joined(separator: ", ") ?? "Unknown Author" }
    var description: String { volumeInfo.description ?? "" }
    var pageCount: Int?     { volumeInfo.pageCount }
    var rating: Double?     { volumeInfo.averageRating }

    /// Returns an https cover URL (Google Books returns http, which ATS blocks).
    var coverUrl: String? {
        guard let thumb = volumeInfo.imageLinks?.thumbnail else { return nil }
        return thumb.replacingOccurrences(of: "http://", with: "https://")
    }
}
