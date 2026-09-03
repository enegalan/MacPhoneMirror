import AppKit
import MacPhoneMirrorCore
import MacPhoneMirrorUI
import SwiftUI

@main
struct MacPhoneMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var sessionManager = SessionManager.shared

    private var aboutLogo: NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var menuBarStatusImage: NSImage? {
        MenuBarStatusIcon.image(
            for: sessionManager.isServiceEnabled,
            sessions: sessionManager.sessions.count,
            state: sessionManager.state
        )
    }

    var body: some Scene {
        WindowGroup(id: MirrorWindowID.main) {
            MainWindowView()
                .frame(minWidth: 850, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            AboutCommands()
        }

        WindowGroup(id: MirrorWindowID.session, for: String.self) { $sessionID in
            if sessionID.isEmpty {
                Text("No device session")
                    .frame(minWidth: 320, minHeight: 240)
            } else {
                MirrorSessionWindow(sessionID: sessionID)
            }
        } defaultValue: {
            ""
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 480, height: 860)

        WindowGroup(id: MirrorWindowID.about) {
            AboutView(logo: aboutLogo.map { Image(nsImage: $0) })
                .frame(minWidth: 320, minHeight: 340)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarExtraView()
        } label: {
            if let image = menuBarStatusImage {
                Image(nsImage: image)
            } else {
                Image(systemName: "airplayvideo")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.displayName)") {
                openWindow(id: MirrorWindowID.about)
            }
        }
    }
}
