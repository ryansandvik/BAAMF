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

        var request = URLRequest(url: url)
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no response body"
            throw AppError.unknown("HTTP \(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(GoogleBooksSearchResponse.self, from: data)
        let raw = decoded.items ?? []
        return Self.cull(raw)
    }

    // MARK: - Result culling

    /// Removes low-quality results and collapses duplicate editions.
    ///
    /// Rules applied in order:
    ///  1. Drop items with no title.
    ///  2. Drop items where pageCount is nil or zero (usually e-books or metadata stubs).
    ///  3. Deduplicate by (normalised title, normalised author): when the same book appears
    ///     multiple times as different editions, keep the entry with the highest page count
    ///     so the user always sees the most concrete data point.
    private static func cull(_ items: [GoogleBooksItem]) -> [GoogleBooksItem] {
        // 1 & 2 — baseline quality filter
        let filtered = items.filter { item in
            !item.title.isEmpty && (item.pageCount ?? 0) > 0
        }

        // 3 — deduplicate editions
        var seen: [String: GoogleBooksItem] = [:]
        for item in filtered {
            let key = normalise(item.title) + "|" + normalise(item.author)
            if let existing = seen[key] {
                // Keep whichever has the higher page count
                if (item.pageCount ?? 0) > (existing.pageCount ?? 0) {
                    seen[key] = item
                }
            } else {
                seen[key] = item
            }
        }

        // Restore the original relative order so results don't feel shuffled
        return filtered
            .filter { seen[normalise($0.title) + "|" + normalise($0.author)]?.id == $0.id }
    }

    private static func normalise(_ string: String) -> String {
        string
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}
