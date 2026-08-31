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
    }
}
