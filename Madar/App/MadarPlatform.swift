import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The few app-wide system asks that differ between iPhone/iPad and the Mac. Shared code calls these instead of `UIApplication`,
/// so the same session runs in both apps without a platform branch at every call site.
@MainActor enum MadarPlatform {
    /// Where the store, snapshots and backups live. iOS shares the App Group with the widgets and intents (RA2: only the app opens
    /// the store, extensions read snapshots and write the inbox). The Mac app has no extension yet, so it keeps everything in its
    /// own Application Support folder (inside its sandbox container when signed).
    static var dataDirectory: URL? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2")
        #else
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appending(path: "Madar", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
        #endif
    }
    /// iOS locks the store's files while the device is locked; the Mac has no such state for a running app.
    static var isProtectedDataAvailable: Bool {
        #if os(iOS)
        UIApplication.shared.isProtectedDataAvailable
        #else
        true
        #endif
    }
    /// True only when iOS has moved the app to the background; a Mac window never suspends the app this way.
    static var isInBackground: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .background
        #else
        false
        #endif
    }
    /// The wide iPad sizes (taller prayer arch, wider columns). The Mac window uses them too.
    static var usesPadMetrics: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }
    /// The app's own page in system settings (location, notifications and the rest).
    static func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #else
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
    /// Puts the keyboard away (iOS) or ends the field's editing (Mac).
    static func endEditing() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #else
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
    /// Reminders and prayer notifications. The iOS coordinator is not on the Mac yet, so the Mac shows no reminder settings or
    /// permission asks that would do nothing there.
    static var hasNotifications: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
    /// Home Screen widgets and the widget maker are an iPhone/iPad feature; the Mac app has no widget extension yet.
    static var hasHomeScreenWidgets: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
    /// For the startup-recovery report: the system and its version.
    static var systemDescription: String {
        #if os(iOS)
        "iOS \(UIDevice.current.systemVersion)"
        #else
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }
    static func openNotificationSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #else
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}
