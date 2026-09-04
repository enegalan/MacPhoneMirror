import AppKit
import MacPhoneMirrorCore
import MacPhoneMirrorUI
import SwiftUI

@main
struct MacPhoneMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var sessionManager = SessionManager.shared

    private var menuBarStatusImage: NSImage? {
        MenuBarStatusIcon.image(
            for: sessionManager.isServiceEnabled,
            sessions: sessionManager.sessions.count,
            state: sessionManager.state
        )
    }

    private var aboutLogo: NSImage? {
        AppResources.image(forResource: "logo", withExtension: "png")
    }

    var body: some Scene {
        WindowGroup(id: MirrorWindowID.main) {
            MainWindowView()
                .frame(minWidth: 850, minHeight: 650)
                .background(DiagnosticAutoLauncher())
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
        .handlesExternalEvents(matching: [])

        WindowGroup(id: MirrorWindowID.about) {
            AboutView(logo: aboutLogo.map { Image(nsImage: $0) })
                .frame(minWidth: 320, minHeight: 340)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        WindowGroup(id: MirrorWindowID.testPattern, for: String.self) { $sessionID in
            if let sessionID,
               let session = SessionManager.shared.session(id: sessionID)
            {
                MirrorViewportView(
                    sessionID: session.id,
                    device: session.device,
                    orientation: session.orientation
                )
                .frame(minWidth: 420, minHeight: 720)
                .onDisappear {
                    SessionManager.shared.disconnect(sessionID: sessionID)
                }
            } else {
                Text("Test pattern not available")
                    .frame(minWidth: 420, minHeight: 720)
            }
        }
        .windowStyle(.titleBar)

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

/// When launched with `--test-pattern`, automatically starts the synthetic
/// test-pattern session and opens its window. Used to diagnose whether a
/// black screen lives in the Metal render path or the AirPlay decode path.
private struct DiagnosticAutoLauncher: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didLaunch = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard !didLaunch else { return }
                didLaunch = true
                if CommandLine.arguments.contains("--test-pattern") {
                    if let sessionID = SessionManager.shared.startTestPattern() {
                        openWindow(id: MirrorWindowID.testPattern, value: sessionID)
                    }
                }
            }
    }
}
