import SwiftUI
import MacPhoneMirrorCore

public struct MenuBarExtraView: View {
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
            
            if let device = state.activeDevice {
                Text("Mirroring: \(device.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Stop Mirroring") {
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
