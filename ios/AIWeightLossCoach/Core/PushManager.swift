import FirebaseCore
import FirebaseMessaging
import Foundation
import Observation
import UIKit
import UserNotifications
 
@MainActor
@Observable
final class PushManager: NSObject {
    var isAuthorized = false
    var latestToken: String?
 
    private let center = UNUserNotificationCenter.current()
 
    func configureFirebase() {
    // Set this first — local water reminders work with or without Firebase.
    center.delegate = self

    guard FirebaseBootstrap.configure() else { return }
    Messaging.messaging().delegate = self
}
 
    func requestAuthorization() async {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            if isAuthorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isAuthorized = false
        }
    }
 
    func refreshAuthorizationState() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
 
    func registerToken(_ token: String) async {
        latestToken = token
        let body: [String: String] = [
            "token": token,
            "platform": "ios",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        ]
        _ = try? await APIClient.shared.postVoid("notifications/devices", body: body)
    }
 
    func unregisterCurrentToken() async {
        guard let latestToken else { return }
        _ = try? await APIClient.shared.delete("notifications/devices/\(latestToken)")
    }
 
    /// Local fallback so reminders still fire when push is unavailable.
    func scheduleLocalWaterReminders(intervalMinutes: Int, startHour: Int, endHour: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: waterIdentifiers)
        guard isAuthorized, intervalMinutes > 0 else { return }
 
        let content = UNMutableNotificationContent()
        content.title = "Time for water"
        content.body = "A glass now keeps you on track for today's goal."
        content.sound = .default
 
        var hour = startHour
        var index = 0
        while hour <= endHour && index < 8 {
            var components = DateComponents()
            components.hour = hour
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "water-\(index)", content: content, trigger: trigger)
            try? await center.add(request)
            hour += max(intervalMinutes / 60, 1)
            index += 1
        }
    }
 
    private var waterIdentifiers: [String] { (0..<8).map { "water-\($0)" } }
}
 
extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await registerToken(fcmToken) }
    }
}
 
extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
 
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // `applicationIconBadgeNumber` is deprecated as of iOS 17; the
        // notification centre owns the badge count now.
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
