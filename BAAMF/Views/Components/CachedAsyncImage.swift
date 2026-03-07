import SwiftUI

/// Drop-in replacement for SwiftUI's `AsyncImage` that caches loaded images in
/// `ImageCache` for the lifetime of the app session.
///
/// The first time a URL is loaded, the image is fetched over the network and stored
/// in the in-memory cache. Every subsequent use of the same URL on any screen returns
/// the cached `UIImage` instantly — no network request, no placeholder flash.
///
/// Usage is identical to `AsyncImage`:
/// ```swift
/// CachedAsyncImage(url: someURL) { phase in
///     switch phase {
///     case .success(let image): image.resizable().scaledToFill()
///     case .failure, .empty:   placeholderView
///     @unknown default:        placeholderView
///     }
/// }
/// ```
struct CachedAsyncImage<Content: View>: View {

    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    /// Phase is pre-populated from the cache when possible so cached images
    /// appear instantly with no placeholder flash.
    @State private var phase: AsyncImagePhase

    init(url: URL?,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content

        // If the image is already cached, start in .success to avoid any
        // placeholder flicker on re-renders or navigation transitions.
        if let url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            // Re-runs whenever the URL changes (e.g., avatar URL updated).
            .task(id: url) { await load() }
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        guard let url else {
            phase = .empty
            return
        }

        // Cache hit — already shown via init, but also handles the case where
        // another task cached it between our init check and this task running.
        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        // Network fetch. URLSession's own disk cache (sized in BAAMFApp.init)
        // provides a second caching layer for URLs with valid HTTP cache headers.
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            ImageCache.shared.store(uiImage, for: url)
            withAnimation(.easeIn(duration: 0.15)) {
                phase = .success(Image(uiImage: uiImage))
            }
        } catch {
            // Don't overwrite a cached success if the task was cancelled mid-flight
            // (e.g., the view disappeared while loading).
            if !Task.isCancelled {
                phase = .failure(error)
            }
        }
    }
}
