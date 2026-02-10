import Foundation
import UserNotifications

@Observable
final class NotificationService {
    private let notificationCenter = UNUserNotificationCenter.current()

    init() {
        requestAuthorization()
    }

    /// Requests authorization to display notifications
    private func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
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
        sendNotification(title: title, message: message, identifier: "error", sound: .defaultCritical)
    }

    /// Displays a backup success notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    func showBackupSuccess(title: String, message: String) {
        sendNotification(title: title, message: message, identifier: "backup-success", sound: .default)
    }

    /// Displays a backup reminder notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    func showBackupReminder(title: String, message: String) {
        sendNotification(title: title, message: message, identifier: "backup-reminder", sound: .default)
    }

    /// Displays a restore success notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
    func showRestoreSuccess(title: String, message: String) {
        sendNotification(title: title, message: message, identifier: "restore-success", sound: .default)
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
