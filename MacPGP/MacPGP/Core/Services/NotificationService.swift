import Foundation
import UserNotifications

@Observable
final class NotificationService {
    private static let authorizationQueue = DispatchQueue(label: "com.macpgp.notification-authorization")
    private static var hasRequestedAuthorizationThisSession = false

    private let notificationCenter = UNUserNotificationCenter.current()

    /// Requests authorization to display notifications when permission has not been decided yet.
    func requestAuthorizationIfNeeded() {
        Self.requestAuthorizationIfNeeded(on: notificationCenter)
    }

    /// Requests authorization to display notifications when permission has not been decided yet.
    static func requestAuthorizationIfNeeded(on notificationCenter: UNUserNotificationCenter = .current()) {
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            authorizationQueue.async {
                guard !hasRequestedAuthorizationThisSession else {
                    return
                }

                hasRequestedAuthorizationThisSession = true

                notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                    if let error = error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Displays a success notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    func showSuccess(title: String, message: String) {
        sendNotification(title: title, message: message, identifier: "success", sound: .default)
    }

    /// Displays an error notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    func showError(title: String, message: String) {
        sendNotification(title: title, message: message, identifier: "error", sound: .default)
    }

    /// Sends a notification to the user
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    ///   - identifier: A unique identifier for the notification
    ///   - sound: The sound to play with the notification
    private func sendNotification(title: String, message: String, identifier: String, sound: UNNotificationSound) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = sound

        let request = UNNotificationRequest(
            identifier: "\(identifier)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
