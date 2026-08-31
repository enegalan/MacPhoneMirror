import SwiftUI
import MacPhoneMirrorCore
import MacPhoneMirrorUI

@main
struct MacPhoneMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 850, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mirroring") {
                Button("Go to Home Screen") {
                    Task { try? await SessionManager.shared.sendInputEvent(.homeButton) }
                }
                .keyboardShortcut("h", modifiers: .command)

                Button("App Switcher") {
                    Task { try? await SessionManager.shared.sendInputEvent(.appSwitcher) }
                }
                .keyboardShortcut(.tab, modifiers: .command)

                Button("Lock Screen") {
                    Task { try? await SessionManager.shared.sendInputEvent(.lockScreen) }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
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
    }
}
