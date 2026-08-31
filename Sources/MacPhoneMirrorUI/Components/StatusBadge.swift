import SwiftUI
import MacPhoneMirrorCore

public struct StatusBadge: View {
    public let state: ConnectionState
    
    public init(state: ConnectionState) {
        self.state = state
    }
    
    private var color: Color {
        switch state {
        case .connected, .mirroring, .controlling:
            return .green
        case .discovering, .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return .secondary
        }
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3, x: 0, y: 0)
            
            Text(state.statusDescription)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
        )
    }
}
