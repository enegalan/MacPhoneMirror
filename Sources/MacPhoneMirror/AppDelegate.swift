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

    private func logoImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func applyAppIcon() {
        if let image = logoImage() {
            NSApp.applicationIconImage = image
        }
    }
}
