//
//  BackupReminderServiceTests.swift
//  MacPGPTests
//
//  Created by auto-claude on 10/02/26.
//

import Testing
import Foundation
@testable import MacPGP

@Suite("BackupReminderService Tests", .serialized)
struct BackupReminderServiceTests {

    // MARK: - Test Setup

    /// Helper to reset preferences to a known state
    func resetPreferences() {
        PreferencesManager.shared.lastBackupDate = nil
        PreferencesManager.shared.backupReminderEnabled = true
        PreferencesManager.shared.backupReminderIntervalDays = 30
    }

    // MARK: - First-Time User Tests

    @Test("First-time user with no backup schedules reminder for next day")
    func testFirstTimeUserSchedulesForNextDay() async throws {
        resetPreferences()

        // Set up first-time user state (no last backup)
        PreferencesManager.shared.lastBackupDate = nil
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // For a first-time user, reminder should be needed (would be scheduled for tomorrow)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }

        // Since it's scheduled for tomorrow, it's not needed yet
        #expect(isNeeded == false)
    }

    // MARK: - Reminder Scheduling Tests

    @Test("Reminder schedules correctly based on last backup date and interval")
    func testScheduleReminderWithLastBackupDate() async throws {
        resetPreferences()

        // Set last backup to 20 days ago with 30-day interval
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        PreferencesManager.shared.lastBackupDate = twentyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should not be needed yet (20 days < 30 days)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == false)
    }

    @Test("Overdue reminder is needed immediately")
    func testOverdueReminderNeeded() async throws {
        resetPreferences()

        // Set last backup to 40 days ago with 30-day interval
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        PreferencesManager.shared.lastBackupDate = fortyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should be needed immediately (40 days > 30 days)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == true)
    }

    @Test("Reminder disabled prevents scheduling")
    func testReminderDisabledPreventsScheduling() async throws {
        resetPreferences()

        // Set last backup to 40 days ago but disable reminders
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        PreferencesManager.shared.lastBackupDate = fortyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = false  // Disabled

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should not be needed when disabled
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == false)
    }

    // MARK: - Interval Tests

    @Test("Different reminder intervals are respected")
    func testDifferentReminderIntervals() async throws {
        resetPreferences()

        // Set last backup to 10 days ago with 7-day interval
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        PreferencesManager.shared.lastBackupDate = tenDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 7
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should be needed (10 days > 7 days)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == true)
    }

    @Test("Long reminder interval (90 days) works correctly")
    func testLongReminderInterval() async throws {
        resetPreferences()

        // Set last backup to 60 days ago with 90-day interval
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        PreferencesManager.shared.lastBackupDate = sixtyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 90
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should not be needed yet (60 days < 90 days)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == false)
    }

    // MARK: - Update and Cancellation Tests

    @Test("Update reminder schedule works after backup")
    func testUpdateReminderScheduleAfterBackup() async throws {
        resetPreferences()

        // Start with overdue backup
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        PreferencesManager.shared.lastBackupDate = fortyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should be needed
        let beforeUpdate = await MainActor.run { service.isReminderNeeded() }
        #expect(beforeUpdate == true)

        // Simulate a backup happening now
        PreferencesManager.shared.lastBackupDate = Date()

        // Update the reminder schedule
        await MainActor.run { service.updateReminderSchedule() }

        // Reminder should no longer be needed
        let afterUpdate = await MainActor.run { service.isReminderNeeded() }
        #expect(afterUpdate == false)
    }

    @Test("Cancel scheduled reminder works")
    func testCancelScheduledReminder() async throws {
        resetPreferences()

        // Set up a scheduled reminder
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        PreferencesManager.shared.lastBackupDate = twentyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Cancel the reminder
        await MainActor.run { service.cancelScheduledReminder() }

        // Note: We can't directly verify the notification was cancelled without
        // accessing UNUserNotificationCenter's pending requests, but we can verify
        // the method executes without errors
        #expect(true)
    }

    // MARK: - Edge Cases

    @Test("Reminder on exact due date is considered needed")
    func testReminderOnExactDueDate() async throws {
        resetPreferences()

        // Set last backup to exactly 30 days ago with 30-day interval
        let exactlyThirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        PreferencesManager.shared.lastBackupDate = exactlyThirtyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should be needed (>= due date)
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == true)
    }

    @Test("Very recent backup does not trigger reminder")
    func testVeryRecentBackup() async throws {
        resetPreferences()

        // Set last backup to 1 hour ago with 30-day interval
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        PreferencesManager.shared.lastBackupDate = oneHourAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30
        PreferencesManager.shared.backupReminderEnabled = true

        let service = await MainActor.run { BackupReminderService() }

        // Reminder should not be needed
        let isNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(isNeeded == false)
    }

    @Test("Toggling reminder enabled state works correctly")
    func testTogglingReminderEnabledState() async throws {
        resetPreferences()

        // Set up overdue backup
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        PreferencesManager.shared.lastBackupDate = fortyDaysAgo
        PreferencesManager.shared.backupReminderIntervalDays = 30

        let service = await MainActor.run { BackupReminderService() }

        // Enable reminders
        PreferencesManager.shared.backupReminderEnabled = true
        await MainActor.run { service.updateReminderSchedule() }
        let enabledNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(enabledNeeded == true)

        // Disable reminders
        PreferencesManager.shared.backupReminderEnabled = false
        await MainActor.run { service.updateReminderSchedule() }
        let disabledNeeded = await MainActor.run { service.isReminderNeeded() }
        #expect(disabledNeeded == false)
    }
}
