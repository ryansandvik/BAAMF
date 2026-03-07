import UIKit

/// In-memory image cache backed by NSCache.
///
/// NSCache automatically evicts entries under system memory pressure, so there's
/// nothing to manually manage. Images live for the app session — the same profile
/// photo or book cover is only fetched once no matter how many screens display it.
final class ImageCache {

    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Allow up to 150 images or 50 MB in RAM — plenty for a session of
        // profile pictures (~50–150 KB each) and book covers (~20–80 KB each).
        cache.countLimit = 150
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    // MARK: - Access

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// Stores an image, using its compressed byte size as the NSCache cost so
    /// larger images count proportionally against the memory budget.
    func store(_ image: UIImage, for url: URL) {
        let cost = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
