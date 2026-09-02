import Cocoa
import MacPhoneMirrorCore
import MacPhoneMirrorUI
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    public func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("MacPhoneMirror application launched successfully", category: .session)
        applyAppIcon()
        setupMenuBar()

        Task {
            await SessionManager.shared.startListening()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button, let logo = menuBarLogo() {
            button.image = logo
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "MacPhoneMirror", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Main Window", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit MacPhoneMirror",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func logoImage() -> NSImage? {
        let bundle = Bundle.module
            .url(forResource: "logo", withExtension: "png", subdirectory: "Assets.xcassets/AppIcon.appiconset")
        guard let url = bundle else { return nil }
        return NSImage(contentsOf: url)
    }

    private func menuBarLogo() -> NSImage? {
        guard let image = logoImage() else { return nil }
        image.size = NSSize(width: 24, height: 24)
        return image
    }

    private func applyAppIcon() {
        if let image = logoImage() {
            NSApp.applicationIconImage = image
        }
    }
}
