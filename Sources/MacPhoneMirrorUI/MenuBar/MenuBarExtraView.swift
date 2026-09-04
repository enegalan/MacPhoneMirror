import AppKit
import MacPhoneMirrorCore
import SwiftUI

public struct MenuBarExtraView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false

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
                MenuActionButton(title: "Test Pattern (Diagnostic)", systemImage: "display") {
                    openTestPattern()
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

    private func updatePulse() {
        let shouldPulse = sessionManager.isServiceEnabled
            && sessionManager.sessions.isEmpty
            && !isFailedState
        isPulsing = shouldPulse
    }

    private var isFailedState: Bool {
        if case .failed = sessionManager.state {
            return true
        }
        return false
    }

    private var serviceIconColor: Color {
        guard sessionManager.isServiceEnabled else { return .secondary }
        if !sessionManager.sessions.isEmpty {
            return .green
        }
        if isFailedState {
            return .red
        }
        return .orange
    }

    private var serviceIconBackgroundOpacity: Double {
        guard sessionManager.isServiceEnabled else { return 0.08 }
        if !sessionManager.sessions.isEmpty {
            return 0.15
        }
        if isFailedState {
            return 0.15
        }
        return 0.18
    }

    private var serviceToggleRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(serviceIconColor.opacity(serviceIconBackgroundOpacity))
                    .frame(width: 36, height: 36)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(serviceIconColor)
                    .opacity(isPulsing ? 0.35 : 1.0)
                    .animation(isPulsing ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isPulsing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AirPlayTXTRecordBuilder.serviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                    Text(serviceStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

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
        guard sessionManager.isServiceEnabled else { return "Service disabled" }
        if !sessionManager.sessions.isEmpty {
            let count = sessionManager.sessions.count
            return "\(count) device\(count == 1 ? "" : "s") connected"
        }
        if case let .failed(message) = sessionManager.state {
            return message
        }
        return "Waiting for Connection..."
    }

    private var statusDotColor: Color {
        guard sessionManager.isServiceEnabled else { return .secondary }
        if !sessionManager.sessions.isEmpty {
            return .green
        }
        if case .failed = sessionManager.state {
            return .red
        }
        return .orange
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.starts(with: MirrorWindowID.main) == true && $0.isVisible && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(NSApp)
        } else {
            openWindow(id: MirrorWindowID.main)
        }
        dismiss()
    }

    private func openTestPattern() {
        NSApp.activate(ignoringOtherApps: true)
        if let sessionID = sessionManager.startTestPattern() {
            openWindow(id: MirrorWindowID.testPattern, value: sessionID)
        }
        dismiss()
    }

    private func focusSession(_ session: MirrorSession) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "mirror-session-\(session.id)" && $0.isVisible && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(NSApp)
        } else {
            openWindow(id: MirrorWindowID.session, value: session.id)
        }
        dismiss()
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
