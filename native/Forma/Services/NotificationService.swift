import Foundation
import UserNotifications

struct ReminderScheduleResult {
    let scheduledIds: [String]
    let count: Int
    let message: String
}

/// Schedules local reminders through UNUserNotificationCenter. A schedule is
/// only reported as successful when the system confirms the requests exist.
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "forma."

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    private func removeAppOwned() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Replaces every Forma-owned reminder with the requested schedule.
    func schedule(_ settings: ReminderSettings) async throws -> ReminderScheduleResult {
        guard settings.enabled else {
            await removeAppOwned()
            return ReminderScheduleResult(
                scheduledIds: [],
                count: 0,
                message: "Reminders are off. Nothing is scheduled."
            )
        }

        let status = await authorizationStatus()
        var allowed = status == .authorized || status == .provisional || status == .ephemeral
        if status == .notDetermined {
            allowed = await requestAuthorization()
        }
        guard allowed else {
            await removeAppOwned()
            throw FormaError.message(
                "Notification permission is not granted, so nothing was scheduled. Enable notifications for Forma in iOS Settings."
            )
        }

        await removeAppOwned()

        let (hour, minute) = Formatters.hourMinute(settings.workoutTime)
        let trainingDays = Set(settings.days.filter { (1...7).contains($0) })
        var requests: [UNNotificationRequest] = []

        for day in settings.days.sorted() where (1...7).contains(day) {
            var components = DateComponents()
            components.weekday = day == 7 ? 1 : day + 1
            components.hour = hour
            components.minute = minute
            let content = UNMutableNotificationContent()
            content.title = "Training day"
            content.body = "Your session is ready. Even a short one keeps the habit alive."
            content.sound = .default
            content.threadIdentifier = "forma.workout"
            content.userInfo = ["source": "forma-reminder"]
            requests.append(UNNotificationRequest(
                identifier: "\(prefix)workout.\(day)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }

        if settings.restDayReminders {
            for day in 1...7 where !trainingDays.contains(day) {
                var components = DateComponents()
                components.weekday = day == 7 ? 1 : day + 1
                components.hour = 10
                components.minute = 0
                let content = UNMutableNotificationContent()
                content.title = "Recovery day"
                content.body = "A walk, some gentle mobility, and good sleep is today's work."
                content.sound = nil
                content.threadIdentifier = "forma.rest"
                content.userInfo = ["source": "forma-reminder"]
                requests.append(UNNotificationRequest(
                    identifier: "\(prefix)rest.\(day)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                ))
            }
        }

        if settings.hydrationReminders {
            for (identifier, hourValue) in [("am", 11), ("pm", 16)] {
                var components = DateComponents()
                components.hour = hourValue
                components.minute = 0
                let content = UNMutableNotificationContent()
                content.title = "Water break"
                content.body = "A glass of water now keeps the afternoon steady."
                content.sound = nil
                content.threadIdentifier = "forma.hydration"
                content.userInfo = ["source": "forma-reminder"]
                requests.append(UNNotificationRequest(
                    identifier: "\(prefix)hydration.\(identifier)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                ))
            }
        }

        if settings.weeklyProgressReminder {
            var components = DateComponents()
            components.weekday = 1
            components.hour = 18
            components.minute = 0
            let content = UNMutableNotificationContent()
            content.title = "Your week in Forma"
            content.body = "Take a minute to review your sessions and plan the week ahead."
            content.sound = nil
            content.threadIdentifier = "forma.weekly"
            content.userInfo = ["source": "forma-reminder"]
            requests.append(UNNotificationRequest(
                identifier: "\(prefix)weekly",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }

        var added: [String] = []
        for request in requests {
            try await center.add(request)
            added.append(request.identifier)
        }

        let pending = await center.pendingNotificationRequests()
        let confirmed = added.filter { identifier in pending.contains { $0.identifier == identifier } }
        if confirmed.isEmpty {
            throw FormaError.message("iOS did not keep any reminders. Check notification settings and try again.")
        }

        return ReminderScheduleResult(
            scheduledIds: confirmed,
            count: confirmed.count,
            message: "\(confirmed.count) reminder\(confirmed.count == 1 ? "" : "s") scheduled on this device."
        )
    }

    func cancelAll() async {
        await removeAppOwned()
    }

    func pendingAppOwnedCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }.count
    }
}
