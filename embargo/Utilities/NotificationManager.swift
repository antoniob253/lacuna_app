import UserNotifications
import SwiftUI

struct InAppNotification: Equatable {
    let capsuleID: String
    var customTitle: String?
}

@Observable
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Set when user taps a system notification — the capsule ID to navigate to
    var pendingCapsuleID: String?

    /// Set when a notification fires while app is in foreground — triggers in-app toast
    var inAppNotification: InAppNotification?

    static let categoryID = "CAPSULE_READY"
    static let openActionID = "OPEN_NOW"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let openAction = UNNotificationAction(
            identifier: Self.openActionID,
            title: "open now",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [openAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    var notificationsDenied = false

    func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await checkNotificationStatus()
        }
    }

    func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    static func scheduleCapsuleNotification(id: String, title: String, unlockDate: Date) {
        // Don't schedule for past-due unlocks — the in-app toast already announces
        // those (and a delayed system notif would otherwise replace the custom toast
        // ~1s later with the generic "a time capsule is ready" copy).
        let secondsUntilUnlock = unlockDate.timeIntervalSince(Date.now)
        guard secondsUntilUnlock > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "the wait is over"
        content.body = "a time capsule is ready to be opened."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["capsuleID": id]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: secondsUntilUnlock,
            repeats: false
        )

        let request = UNNotificationRequest(identifier: "capsule-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelCapsuleNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["capsule-\(id)"])
    }

    // Foreground: show custom in-app toast. Background: show system banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }

        if isActive {
            if let capsuleID = notification.request.content.userInfo["capsuleID"] as? String {
                await MainActor.run {
                    inAppNotification = InAppNotification(capsuleID: capsuleID)
                }
            }
            return []
        } else {
            return [.banner, .sound]
        }
    }

    // Handle system notification tap — extract capsule ID for navigation
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let capsuleID = response.notification.request.content.userInfo["capsuleID"] as? String {
            await MainActor.run {
                pendingCapsuleID = capsuleID
            }
        }
    }
}
