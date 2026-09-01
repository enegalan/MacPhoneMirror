import SwiftUI
import MacPhoneMirrorCore

public struct MirrorSessionWindow: View {
    public let sessionID: String

    @ObservedObject private var sessionManager = SessionManager.shared
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
        .onDisappear {
            SessionManager.shared.disconnect(sessionID: sessionID)
        }
    }

    private var windowTitle: String {
        sessionManager.session(id: sessionID)?.device.name
            ?? sessionManager.sessions.first(where: { $0.id == sessionID })?.device.name
            ?? "iPhone"
    }
}
