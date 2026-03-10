import Foundation
import Combine

// MARK: - Deep-link destinations

/// Represents a navigation target that a push notification tap can request.
enum AppDeepLink: Equatable {
    /// Navigate to the VetoView for the given month document ID.
    case veto(monthId: String)
}

// MARK: - Router

/// Singleton that bridges AppDelegate notification-tap handling to the SwiftUI
/// view hierarchy. AppDelegate writes `pendingLink`; MainTabView and HomeView
/// observe it and perform the actual navigation.
@MainActor
final class DeepLinkRouter: ObservableObject {

    static let shared = DeepLinkRouter()
    private init() {}

    @Published var pendingLink: AppDeepLink?

    /// Reads and clears the pending link atomically.
    func consume() -> AppDeepLink? {
        defer { pendingLink = nil }
        return pendingLink
    }
}
