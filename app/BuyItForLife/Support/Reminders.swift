import Foundation
import SwiftData
import UIKit
import UserNotifications

/// The daily "Nothing logged today" reminder. There is only ever one pending
/// notification; it is rescheduled whenever logging, settings or the day change.
@MainActor
enum Reminders {
    static let identifier = "daily-reminder"

    enum PermissionResult { case granted, denied }

    /// Asks for notification permission if it hasn't been asked yet.
    static func requestPermission() async -> PermissionResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .granted : .denied
        default:
            return .denied
        }
    }

    /// Removes the pending reminder and, if reminders are on, schedules the next one.
    static func reschedule(settings: AppSettings, context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard settings.reminderEnabled else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let fireDate = ReminderPlanner.nextFireDate(
            now: now, minutes: settings.reminderMinutes, loggedToday: isLoggedToday(context: context, now: now)
        )
        let content = UNMutableNotificationContent()
        content.body = "Nothing logged today. What did you wear?"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Today counts as logged once the user has picked at least one item that
    /// isn't a daily driver. Pre-selected daily drivers don't count.
    static func isLoggedToday(context: ModelContext, now: Date = .now) -> Bool {
        let key = DayKey.make(for: now)
        let logs = (try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.dayKey == key }))) ?? []
        return logs.contains { log in (log.items ?? []).contains { !$0.isDailyDriver } }
    }
}

/// Which tab is showing, so a notification tap can open Today.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: RootView.TabID = .today
}

/// Receives notification taps and shows reminders while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { AppRouter.shared.tab = .today }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
