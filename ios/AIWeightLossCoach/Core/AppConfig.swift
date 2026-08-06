import Foundation
import UIKit

enum AppConfig {
    static let apiBaseURL: URL = {
        let fallback = "https://api.awlc.app/api/v1"
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? fallback
        return URL(string: raw) ?? URL(string: fallback)!
    }()

    static let monthlyProductID = "com.awlc.coach.premium.monthly"
    static let annualProductID = "com.awlc.coach.premium.annual"
    static let productIDs = [monthlyProductID, annualProductID]

    static let freeCoachMessagesPerDay = 5
    static let supportEmail = "support@awlc.app"
    static let privacyURL = URL(string: "https://awlc.app/privacy")!
    static let termsURL = URL(string: "https://awlc.app/terms")!
    static let supportURL = URL(string: "https://awlc.app/help")!
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
