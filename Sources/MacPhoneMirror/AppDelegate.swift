import Cocoa
import MacPhoneMirrorCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("\(AppInfo.displayName) application launched successfully", category: .session)
        applyAppIcon()

        Task {
            await SessionManager.shared.startListening()
        }
    }

    private func applyAppIcon() {
        if let image = AppResources.image(forResource: "logo", withExtension: "png") {
            NSApp.applicationIconImage = image
        }
    }
}
