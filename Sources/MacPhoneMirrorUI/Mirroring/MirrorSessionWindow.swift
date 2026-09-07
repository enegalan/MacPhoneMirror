import AppKit
import MacPhoneMirrorCore
import SwiftUI

// One NSWindow/SwiftUI scene per mirrored device.
// Window chrome is a floating iPhone screen (transparent, rounded, no title bar).
// Tears down on real window close only — SwiftUI onDisappear fires during reparent and was killing AirPlay mid-handshake.

public struct MirrorSessionWindow: View {
    public let sessionID: String

    @ObservedObject private var sessionManager = SessionManager.shared
    @Environment(\.dismissWindow) private var dismissWindow

    /// Creates a session window for the given mirror session identifier.
    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public var body: some View {
        Group {
            if let session = resolvedSession {
                MirrorViewportView(
                    sessionID: session.id,
                    device: session.device,
                    orientation: session.orientation
                )
                .background(
                    MirrorWindowChrome(
                        sessionID: sessionID,
                        screenSize: session.orientation.orientedSize(for: session.device.model.pointSize)
                    )
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SessionWindowCloseHook(sessionID: sessionID))
            }
        }
        .frame(minWidth: 200, minHeight: 360)
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
}

/// Configures the mirror NSWindow as a floating phone screen and disconnects on close.
private struct MirrorWindowChrome: NSViewRepresentable {
    let sessionID: String
    let screenSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window, sessionID: sessionID, screenSize: screenSize)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.attach(to: window, sessionID: sessionID, screenSize: screenSize)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var observer: NSObjectProtocol?
        private weak var observedWindow: NSWindow?
        private var sessionID: String = ""
        private var lastScreenSize: CGSize = .zero
        private var didApplyInitialSize = false

        @MainActor
        func attach(to window: NSWindow, sessionID: String, screenSize: CGSize) {
            self.sessionID = sessionID
            configureChrome(window)

            if observer == nil || observedWindow !== window {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                observedWindow = window
                let closingSessionID = sessionID
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    AppLogger.info("Mirror window closing, disconnect \(closingSessionID)", category: .session)
                    SessionManager.shared.disconnect(sessionID: closingSessionID)
                }
            }

            applyScreenGeometry(window, screenSize: screenSize)
        }

        @MainActor
        private func configureChrome(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        @MainActor
        private func applyScreenGeometry(_ window: NSWindow, screenSize: CGSize) {
            guard screenSize.width > 0, screenSize.height > 0 else { return }

            window.contentAspectRatio = screenSize

            if !didApplyInitialSize {
                didApplyInitialSize = true
                lastScreenSize = screenSize
                let defaultWidth: CGFloat = 360
                let defaultHeight = defaultWidth * (screenSize.height / screenSize.width)
                window.setContentSize(NSSize(width: defaultWidth, height: defaultHeight))
                return
            }

            guard lastScreenSize != screenSize else { return }

            let current = window.contentLayoutRect.size
            let previous = lastScreenSize
            lastScreenSize = screenSize

            // Keep visual scale when rotating between portrait and landscape.
            let scale = previous.width > 0
                ? current.width / previous.width
                : current.height / max(previous.height, 1)
            let newSize = NSSize(
                width: screenSize.width * scale,
                height: screenSize.height * scale
            )
            window.setContentSize(newSize)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// Tears down the session only when the NSWindow actually closes (connecting placeholder).
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

        @MainActor
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
            let closingSessionID = sessionID
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                AppLogger.info("Mirror window closing, disconnect \(closingSessionID)", category: .session)
                SessionManager.shared.disconnect(sessionID: closingSessionID)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
