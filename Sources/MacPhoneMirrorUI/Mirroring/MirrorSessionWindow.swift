import AppKit
import MacPhoneMirrorCore
import SwiftUI

public struct MirrorSessionWindow: View {
    public let sessionID: String

    @ObservedObject private var sessionManager = SessionManager.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var frameStyle = FrameRenderStyle.standard

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public var body: some View {
        Group {
            if let session = sessionManager.session(id: sessionID) ?? sessionManager.sessions.first(where: { $0.id == sessionID }) {
                MirrorViewportView(
                    sessionID: session.id,
                    device: session.device,
                    orientation: session.orientation,
                    style: frameStyle
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 420, minHeight: 720)
        .navigationTitle(windowTitle)
        .background(SessionWindowCloseHook(sessionID: sessionID))
        .onAppear {
            // SwiftUI restores the last session window on launch with a stale id.
            // That shows "Connecting…" forever and confuses the AirPlay flow.
            if sessionManager.session(id: sessionID) == nil,
               !sessionManager.sessions.contains(where: { $0.id == sessionID })
            {
                AppLogger.info(
                    "Dismissing restored mirror window with no live session: \(sessionID)",
                    category: .session
                )
                dismissWindow(id: MirrorWindowID.session, value: sessionID)
            }
        }
    }

    private var windowTitle: String {
        sessionManager.session(id: sessionID)?.device.name
            ?? sessionManager.sessions.first(where: { $0.id == sessionID })?.device.name
            ?? "iPhone"
    }
}

/// Tears down the session only when the NSWindow actually closes.
/// SwiftUI `onDisappear` fires during reparent/layout and was killing AirPlay
/// mid-handshake.
private struct SessionWindowCloseHook: NSViewRepresentable {
    let sessionID: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window, sessionID: sessionID)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.attach(to: window, sessionID: sessionID)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var observer: NSObjectProtocol?
        private var sessionID: String = ""

        func attach(to window: NSWindow, sessionID: String) {
            self.sessionID = sessionID
            if observer != nil {
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                AppLogger.info("Mirror window closing, disconnect \(self.sessionID)", category: .session)
                SessionManager.shared.disconnect(sessionID: self.sessionID)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
