import AppKit
import MacPhoneMirrorCore
import SwiftUI

public struct MirrorSessionWindow: View {
    public let sessionID: String

    @ObservedObject private var sessionManager = SessionManager.shared
    @ObservedObject private var frameStyleStore = FrameStyleStore.shared
    @Environment(\.dismissWindow) private var dismissWindow

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public var body: some View {
        Group {
            if let session = resolvedSession {
                MirrorViewportView(
                    sessionID: session.id,
                    device: session.device,
                    orientation: session.orientation,
                    style: frameStyleStore.style
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
        .frame(minWidth: 260, minHeight: 300)
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

    private var resolvedSession: MirrorSession? {
        sessionManager.session(id: sessionID)
            ?? sessionManager.sessions.first { $0.id == sessionID }
    }

    private var windowTitle: String {
        resolvedSession?.device.name ?? "iPhone"
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
        private weak var observedWindow: NSWindow?
        private var sessionID: String = ""

        func attach(to window: NSWindow, sessionID: String) {
            self.sessionID = sessionID
            if observer != nil, observedWindow === window {
                return
            }

            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }

            observedWindow = window
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
