import Cocoa
import MacPhoneMirrorCore

// App lifecycle hook outside SwiftUI.
// Needed so we can disable window restoration (stale mirror windows), force activation,
// apply the dock icon, and start AirPlay listening at launch.

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Disables window restoration, activates the app, sets the dock icon, and starts AirPlay listening.
    public func applicationDidFinishLaunching(_: Notification) {
        // Prevent macOS from restoring a stale mirror session window that shows
        // "Connecting…" with no live AirPlay session.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("\(AppInfo.displayName) application launched successfully", category: .session)
        applyAppIcon()

        Task {
            await SessionManager.shared.startListening()
        }
    }

    /// Sets `NSApp.applicationIconImage` from the bundled `app-icon.png` when available.
    private func applyAppIcon() {
        if let image = AppResources.image(forResource: "app-icon", withExtension: "png") {
            NSApp.applicationIconImage = image
        }
    }
}
