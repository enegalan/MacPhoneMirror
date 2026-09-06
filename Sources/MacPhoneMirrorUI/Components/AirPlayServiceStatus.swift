import MacPhoneMirrorCore
import SwiftUI

// Shared AirPlay receiver status labels/colors for Service view and menu bar.

enum AirPlayServiceStatus {
    /// True when `state` is `.failed`.
    static func isFailed(_ state: ConnectionState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    /// True when the receiver is advertising and idle (no sessions, not failed).
    static func isWaiting(isServiceEnabled: Bool, sessionCount: Int, state: ConnectionState) -> Bool {
        isServiceEnabled && sessionCount == 0 && !isFailed(state)
    }

    /// Status accent: gray off, orange waiting, green connected, red failed.
    static func color(isServiceEnabled: Bool, sessionCount: Int, state: ConnectionState) -> Color {
        guard isServiceEnabled else { return .secondary }
        if sessionCount > 0 {
            return .green
        }
        if isFailed(state) {
            return .red
        }
        return .orange
    }

    /// Short human-readable status line for the current receiver state.
    static func text(isServiceEnabled: Bool, sessionCount: Int, state: ConnectionState) -> String {
        guard isServiceEnabled else { return "Service disabled" }
        if sessionCount > 0 {
            return "\(sessionCount) device\(sessionCount == 1 ? "" : "s") connected"
        }
        if case let .failed(message) = state {
            return message
        }
        return "Waiting for Connection..."
    }
}

/// Compact colored status chip (dot + label) for AirPlay receiver state.
struct AirPlayServiceStatusBadge: View {
    let isServiceEnabled: Bool
    let sessionCount: Int
    let state: ConnectionState

    var body: some View {
        let statusColor = AirPlayServiceStatus.color(
            isServiceEnabled: isServiceEnabled,
            sessionCount: sessionCount,
            state: state
        )
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(
                AirPlayServiceStatus.text(
                    isServiceEnabled: isServiceEnabled,
                    sessionCount: sessionCount,
                    state: state
                )
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(statusColor)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
    }
}
