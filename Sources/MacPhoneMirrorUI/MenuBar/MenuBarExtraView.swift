import MacPhoneMirrorCore
import SwiftUI

public struct MenuBarExtraView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    public let onOpenMainWindow: () -> Void

    public init(onOpenMainWindow: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppInfo.displayName)
                    .font(.headline)
                Spacer()
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

            Button("Open \(AppInfo.displayName) Window") {
                onOpenMainWindow()
            }

            Button("Quit \(AppInfo.displayName)") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
