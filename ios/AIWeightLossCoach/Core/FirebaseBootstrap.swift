//
//  FirebaseBootstrap.swift
//  AIWeightLossCoach
//
//  Configures Firebase without ever aborting launch.
//
//  FirebaseApp.configure() with no arguments raises an uncaught
//  NSException when GoogleService-Info.plist is missing or malformed,
//  which kills the app in didFinishLaunchingWithOptions.
//  FirebaseOptions(contentsOfFile:) returns nil instead, so we
//  validate first and configure only when we have a usable file.
//

import Foundation
import FirebaseCore

@MainActor
enum FirebaseBootstrap {

    /// True once Firebase has been successfully configured.
    /// Check this before touching Messaging, Analytics, Crashlytics, etc.
    private(set) static var isConfigured = false

    /// The reason configuration was skipped, if it was. Useful in a debug screen.
    private(set) static var skipReason: String?

    /// Keys FirebaseOptions needs. A truncated or half-decoded plist
    /// usually parses fine but is missing some of these.
    private static let requiredKeys = [
        "API_KEY",
        "GCM_SENDER_ID",
        "GOOGLE_APP_ID",
        "PROJECT_ID",
        "BUNDLE_ID"
    ]

    @discardableResult
    static func configure() -> Bool {
        // Already up (e.g. called twice, or from a test harness).
        if FirebaseApp.app() != nil {
            isConfigured = true
            return true
        }

        guard let path = Bundle.main.path(
            forResource: "GoogleService-Info",
            ofType: "plist"
        ) else {
            return skip("GoogleService-Info.plist is not in the app bundle. "
                      + "Check the Codemagic decode step and that project.yml "
                      + "lists it as a resource.")
        }

        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return skip("GoogleService-Info.plist exists but is not a readable "
                      + "plist. The base64 value in Codemagic is probably "
                      + "truncated or wrapped across lines.")
        }

        let missing = requiredKeys.filter { key in
            guard let value = dict[key] as? String else { return true }
            return value.isEmpty
        }

        guard missing.isEmpty else {
            return skip("GoogleService-Info.plist is missing or has empty keys: "
                      + missing.joined(separator: ", "))
        }

        // Warn loudly if the plist belongs to a different app. Firebase would
        // configure happily and then silently fail to deliver any push.
        if let plistBundleID = dict["BUNDLE_ID"] as? String,
           let appBundleID = Bundle.main.bundleIdentifier,
           plistBundleID != appBundleID {
            log("BUNDLE_ID mismatch — plist says \(plistBundleID), app is "
              + "\(appBundleID). Push delivery will not work. Re-register the "
              + "iOS app in the Firebase console with the correct bundle ID.")
        }

        guard let options = FirebaseOptions(contentsOfFile: path) else {
            return skip("FirebaseOptions could not be built from the plist.")
        }

        FirebaseApp.configure(options: options)
        isConfigured = true
        log("Firebase configured for project \(options.projectID ?? "unknown").")
        return true
    }

    // MARK: - Private

    private static func skip(_ reason: String) -> Bool {
        skipReason = reason
        isConfigured = false
        log("Firebase NOT configured. Remote push is disabled for this "
          + "session; the rest of the app is unaffected. Reason: \(reason)")
        return false
    }

    private static func log(_ message: String) {
        // Keep this as print/NSLog so it shows up in Console.app and in the
        // TestFlight device log without needing a symbolicated crash report.
        NSLog("[FirebaseBootstrap] %@", message)
    }
}
