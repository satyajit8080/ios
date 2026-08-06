import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct AIWeightLossCoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var session = SessionStore()
    @State private var health = HealthKitManager()
    @State private var store = StoreManager()
    @State private var push = PushManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(health)
                .environment(store)
                .environment(push)
                .tint(Palette.pine)
                .task {
                    push.configureFirebase()
                    store.start()
                    await session.bootstrap()
                    await push.refreshAuthorizationState()
                }
        }
    }
}
