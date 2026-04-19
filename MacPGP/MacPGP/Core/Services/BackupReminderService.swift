import Foundation
import UserNotifications

@Observable
final class BackupReminderService {
    private let notificationCenter = UNUserNotificationCenter.current()

    private let reminderIdentifier = "com.macpgp.backup-reminder"
    private let isTestEnvironment: Bool

    init() {
        // Detect test environment
        self.isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                                 ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
                                 NSClassFromString("XCTestCase") != nil
    }

    /// Schedules a backup reminder notification based on user preferences
    func scheduleReminderIfNeeded() {
        // Skip if in test environment
        guard !isTestEnvironment else { return }

        // Cancel any existing reminder first
        cancelScheduledReminder()

        // Check if reminders are enabled
        guard PreferencesManager.shared.backupReminderEnabled else {
            return
        }

        NotificationService.requestAuthorizationIfNeeded(on: notificationCenter)

        // Calculate when the next reminder should fire
        guard let nextReminderDate = calculateNextReminderDate() else {
            return
        }

        // Only schedule if the date is in the future
        guard nextReminderDate > Date() else {
            // If we're past due, show the reminder immediately
            showBackupReminderIfAllowed()
            return
        }

        scheduleReminder(for: nextReminderDate)
    }

    /// Calculates the next reminder date based on last backup date and interval
    /// - Returns: The date when the next reminder should fire, or nil if not applicable
    private func calculateNextReminderDate() -> Date? {
        let intervalDays = PreferencesManager.shared.backupReminderIntervalDays

        if let lastBackupDate = PreferencesManager.shared.lastBackupDate {
            // Schedule based on last backup + interval
            return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastBackupDate)
        } else {
            // No backup yet, schedule for tomorrow to give user time to set up
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }
    }

    /// Schedules a reminder notification for a specific date
    /// - Parameter date: The date when the reminder should fire
    private func scheduleReminder(for date: Date) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("BackupReminder.Title", comment: "Backup reminder notification title")
        content.body = NSLocalizedString("BackupReminder.Body", comment: "Scheduled backup reminder notification body")
        content.sound = .default
        content.categoryIdentifier = "BACKUP_REMINDER"

        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule backup reminder: \(error.localizedDescription)")
            }
        }
    }

    private func showBackupReminderIfAllowed() {
        let intervalDays = PreferencesManager.shared.backupReminderIntervalDays

        if let lastReminderDate = PreferencesManager.shared.lastBackupReminderDate,
           let nextAllowedDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: lastReminderDate),
           nextAllowedDate > Date() {
            return
        }

        showBackupReminder { [notificationCenter] wasQueued in
            guard wasQueued else { return }

            notificationCenter.getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized ||
                      settings.authorizationStatus == .provisional else {
                    return
                }

                DispatchQueue.main.async {
                    PreferencesManager.shared.lastBackupReminderDate = Date()
                }
            }
        }
    }

    /// Displays a backup reminder notification immediately
    private func showBackupReminder(completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("BackupReminder.Title", comment: "Backup reminder notification title")

        if let lastBackupDate = PreferencesManager.shared.lastBackupDate {
            let daysSinceBackup = Calendar.current.dateComponents([.day], from: lastBackupDate, to: Date()).day ?? 0
            content.body = String.localizedStringWithFormat(
                NSLocalizedString("BackupReminder.BodyWithLastBackup", comment: "Immediate backup reminder body with days since last backup"),
                daysSinceBackup
            )
        } else {
            content.body = NSLocalizedString("BackupReminder.BodyNoBackup", comment: "Immediate backup reminder body when no backup exists")
        }

        content.sound = .default
        content.categoryIdentifier = "BACKUP_REMINDER"

        let request = UNNotificationRequest(
            identifier: "\(reminderIdentifier)-immediate",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to deliver backup reminder: \(error.localizedDescription)")
            }
            completion(error == nil)
        }
    }

    /// Cancels any scheduled backup reminder
    func cancelScheduledReminder() {
        guard !isTestEnvironment else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }

    /// Updates the reminder schedule (call this when preferences change or after a successful backup)
    func updateReminderSchedule() {
        guard !isTestEnvironment else { return }
        scheduleReminderIfNeeded()
    }

    /// Checks if a backup reminder is currently needed
    /// - Returns: True if a reminder should be shown based on the last backup date
    func isReminderNeeded() -> Bool {
        guard PreferencesManager.shared.backupReminderEnabled else {
            return false
        }

        guard let nextReminderDate = calculateNextReminderDate() else {
            return true // No backup yet, reminder is needed
        }

        return Date() >= nextReminderDate
    }
}
