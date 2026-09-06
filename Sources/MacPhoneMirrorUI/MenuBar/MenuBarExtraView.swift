import AppKit
import MacPhoneMirrorCore
import SwiftUI

// Menu bar dropdown: service toggle, session shortcuts, open main window.

public struct MenuBarExtraView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false

    /// Creates the menu-bar dropdown bound to the shared session manager.
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            serviceToggleRow
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            devicesSection
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            VStack(spacing: 2) {
                MenuActionButton(title: "Open \(AppInfo.displayName)", systemImage: "macwindow") {
                    openMainWindow()
                }
                MenuActionButton(title: "Quit \(AppInfo.displayName)", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
        .frame(width: 300)
        .onChange(of: sessionManager.isServiceEnabled) { _, _ in updatePulse() }
        .onChange(of: sessionManager.sessions.isEmpty) { _, _ in updatePulse() }
        .onChange(of: sessionManager.state) { _, _ in updatePulse() }
        .onAppear { updatePulse() }
    }

    /// Updates the waiting-for-connection pulse based on service and session state.
    private func updatePulse() {
        isPulsing = AirPlayServiceStatus.isWaiting(
            isServiceEnabled: sessionManager.isServiceEnabled,
            sessionCount: sessionManager.sessions.count,
            state: sessionManager.state
        )
    }

    private var serviceIconColor: Color {
        AirPlayServiceStatus.color(
            isServiceEnabled: sessionManager.isServiceEnabled,
            sessionCount: sessionManager.sessions.count,
            state: sessionManager.state
        )
    }

    private var serviceIconBackgroundOpacity: Double {
        guard sessionManager.isServiceEnabled else { return 0.08 }
        if !sessionManager.sessions.isEmpty {
            return 0.15
        }
        if AirPlayServiceStatus.isFailed(sessionManager.state) {
            return 0.15
        }
        return 0.18
    }

    private var serviceToggleRow: some View {
        HStack(spacing: 10) {
            serviceStatusIcon
            serviceStatusLabels
            Spacer(minLength: 8)
            Toggle(
                "AirPlay service",
                isOn: Binding(
                    get: { sessionManager.isServiceEnabled },
                    set: { sessionManager.setServiceEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private var serviceStatusIcon: some View {
        ZStack {
            Circle()
                .fill(serviceIconColor.opacity(serviceIconBackgroundOpacity))
                .frame(width: 36, height: 36)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(serviceIconColor)
                .opacity(isPulsing ? 0.35 : 1.0)
                .animation(pulseAnimation, value: isPulsing)
        }
    }

    private var pulseAnimation: Animation {
        isPulsing ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default
    }

    private var serviceStatusLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AirPlayTXTRecordBuilder.serviceName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 5) {
                Circle()
                    .fill(serviceIconColor)
                    .frame(width: 6, height: 6)
                Text(serviceStatusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        if sessionManager.sessions.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                Text("No devices connected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        } else {
            ForEach(sessionManager.sessions) { session in
                DeviceSessionButton(session: session) {
                    focusSession(session)
                }
            }
        }
    }

    private var serviceStatusText: String {
        AirPlayServiceStatus.text(
            isServiceEnabled: sessionManager.isServiceEnabled,
            sessionCount: sessionManager.sessions.count,
            state: sessionManager.state
        )
    }

    /// Brings the main app window forward, opening it if needed.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = visibleWindow(where: { identifier in
            identifier.starts(with: MirrorWindowID.main)
        }) {
            window.makeKeyAndOrderFront(NSApp)
        } else {
            openWindow(id: MirrorWindowID.main)
        }
        dismiss()
    }

    /// Focuses an existing mirror session window or opens a new one.
    private func focusSession(_ session: MirrorSession) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = visibleWindow(where: { identifier in
            identifier == "mirror-session-\(session.id)"
        }) {
            window.makeKeyAndOrderFront(NSApp)
        } else {
            openWindow(id: MirrorWindowID.session, value: session.id)
        }
        dismiss()
    }

    /// Finds the first visible non-panel window whose identifier matches the predicate.
    private func visibleWindow(where match: (String) -> Bool) -> NSWindow? {
        NSApp.windows.first { window in
            guard let identifier = window.identifier?.rawValue else { return false }
            return match(identifier) && window.isVisible && !(window is NSPanel)
        }
    }
}

private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct DeviceSessionButton: View {
    let session: MirrorSession
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: session.device.connectionType.iconName)
                    .font(.system(size: 12))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.device.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(session.device.connectionType.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
