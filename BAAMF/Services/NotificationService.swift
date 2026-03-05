import Foundation
import UserNotifications
import UIKit
import FirebaseFirestore

/// Handles push notification permission requests and FCM token storage.
/// The App Delegate drives the APNS/FCM token lifecycle; this service
/// is responsible for persisting those tokens to Firestore so Cloud
/// Functions can target specific devices.
final class NotificationService {

    static let shared = NotificationService()

    private let db = FirestoreService.shared

    private init() {}

    // MARK: - Permission

    /// Requests notification authorization and, if granted, registers for remote notifications.
    /// Safe to call repeatedly — the system will only prompt once.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Token storage

    /// Writes the FCM token to the user's Firestore document.
    /// Called after sign-in and whenever FCM rotates the token.
    func saveFCMToken(_ token: String, for userId: String) {
        db.userRef(uid: userId).updateData(["fcmToken": token]) { error in
            if let error {
                print("NotificationService: failed to save FCM token – \(error.localizedDescription)")
            }
        }
    }

    /// Removes the FCM token on sign-out so the user stops receiving notifications.
    func clearFCMToken(for userId: String) {
        db.userRef(uid: userId).updateData(["fcmToken": FieldValue.delete()]) { _ in }
    }
}
