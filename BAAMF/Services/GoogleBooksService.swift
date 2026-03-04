import Foundation

/// Wraps the Google Books API. Uses URLSession + Codable — no third-party dependencies.
final class GoogleBooksService {

    static let shared = GoogleBooksService()
    private init() {}

    /// Search for books matching `query`. Returns up to `K.GoogleBooks.maxResults` results.
    func search(query: String) async throws -> [GoogleBooksItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let apiKey = K.GoogleBooks.apiKey
        guard !apiKey.isEmpty else {
            throw AppError.unknown("Google Books API key is not configured. Check Config.xcconfig.")
        }

        var components = URLComponents(string: K.GoogleBooks.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "q",          value: trimmed),
            URLQueryItem(name: "maxResults", value: String(K.GoogleBooks.maxResults)),
            URLQueryItem(name: "printType",  value: "books"),
            URLQueryItem(name: "key",        value: apiKey)
        ]

        guard let url = components.url else {
            throw AppError.unknown("Could not build Google Books URL.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError.unknown("Google Books API error (HTTP \(http.statusCode)).")
        }

        let decoded = try JSONDecoder().decode(GoogleBooksSearchResponse.self, from: data)
        return decoded.items ?? []
    }
}
