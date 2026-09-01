import SwiftUI
import MacPhoneMirrorCore

public struct MenuBarExtraView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    public let state: ConnectionState
    public let onOpenMainWindow: () -> Void

    public init(state: ConnectionState, onOpenMainWindow: @escaping () -> Void) {
        self.state = state
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MacPhoneMirror")
                    .font(.headline)
                Spacer()
                StatusBadge(state: state)
            }
            .padding(.bottom, 4)

            Divider()

            if !sessionManager.sessions.isEmpty {
                ForEach(sessionManager.sessions) { session in
                    Text("Mirroring: \(session.device.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Stop All Mirroring") {
                    SessionManager.shared.disconnect()
                }
            } else {
                Text("Waiting for Screen Mirroring from iPhone")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Open MacPhoneMirror Window") {
                onOpenMainWindow()
            }

            Button("Quit MacPhoneMirror") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
