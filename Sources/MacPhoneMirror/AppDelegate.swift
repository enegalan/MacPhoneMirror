import Cocoa
import MacPhoneMirrorCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
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

    private func applyAppIcon() {
        if let image = AppResources.image(forResource: "app-icon", withExtension: "png") {
            NSApp.applicationIconImage = image
        }
    }
}
