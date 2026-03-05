import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import UIKit

// MARK: - App delegate

private class AppDelegate: NSObject, UIApplicationDelegate,
                            UNUserNotificationCenterDelegate,
                            MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Receive notifications when the app is in the foreground
        UNUserNotificationCenter.current().delegate = self
        // Receive FCM token refresh callbacks
        Messaging.messaging().delegate = self
        return true
    }

    // MARK: Orientation lock

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    // MARK: APNS token → FCM SDK

    /// Pass the raw APNS device token to the FCM SDK so it can exchange it
    /// for an FCM registration token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: FCM token refresh

    /// Called when the FCM SDK gets a new (or rotated) registration token.
    /// We broadcast it so AuthViewModel can persist it to Firestore for the
    /// current user.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        NotificationCenter.default.post(
            name: .fcmTokenRefreshed,
            object: fcmToken
        )
    }

    // MARK: Foreground notification display

    /// Show banners + play sound even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted by AppDelegate when the FCM registration token is issued or rotated.
    /// The `object` property contains the token `String`.
    static let fcmTokenRefreshed = Notification.Name("FCMTokenRefreshed")
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
