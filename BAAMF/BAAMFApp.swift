import SwiftUI
import FirebaseCore
import UIKit

// MARK: - App delegate (portrait-only lock)

private class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

// MARK: - App

@main
struct BAAMFApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}

// MARK: - RootView

/// Top-level view that switches between the login screen and the main app
/// based on auth state.
struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isLoading {
                // Shown briefly while Firebase resolves the auth state on launch
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        ProgressView()
                    }
                }
            } else if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authViewModel.isAuthenticated)
        .animation(.easeInOut(duration: 0.2), value: authViewModel.isLoading)
    }
}
