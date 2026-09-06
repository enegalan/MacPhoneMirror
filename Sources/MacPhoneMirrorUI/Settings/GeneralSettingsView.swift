import MacPhoneMirrorCore
import SwiftUI

// Launch at login, permissions, and other non-stream preferences.

public struct GeneralSettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    /// Creates the General settings pane with current launch-at-login state.
    public init() {}

    public var body: some View {
        SettingsCard(title: "General", subtitle: "Startup & connection behavior", icon: "gearshape") {
            ToggleRow(
                icon: "power",
                tint: .orange,
                title: "Launch \(AppInfo.displayName) at Login",
                subtitle: "Start automatically whenever you log in to this Mac.",
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                )
            )

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.leading, 38)
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SystemPermission.allCases) { permission in
                    PermissionStatusRow(permission: permission)
                        .padding(.vertical, 3)
                }
            }
        }
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    /// Enables or disables Launch at Login and surfaces any SMAppService error.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = error.localizedDescription
            AppLogger.error("Launch at login failed: \(error.localizedDescription)", category: .session)
        }
    }
}

private struct PermissionStatusRow: View {
    let permission: SystemPermission
    @State private var hasResolvedStatus = false
    @State private var isGranted = false
    @State private var isHovered = false

    private var permissionIcon: String {
        switch permission {
        case .localNetwork: "wifi"
        case .bluetooth: "dot.radiowaves.left.and.right"
        }
    }

    private var permissionTint: Color {
        switch permission {
        case .localNetwork: .blue
        case .bluetooth: .indigo
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowIcon(permissionIcon, tint: permissionTint)
            permissionLabel
            Spacer()
            statusIndicator
            settingsLinkButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            isGranted = PermissionManager.shared.checkPermissionStatus(permission)
            hasResolvedStatus = true
        }
    }

    private var permissionLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(permission.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Text(permission.reasonDescription)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if hasResolvedStatus {
            Text(isGranted ? "Granted" : "Not Granted")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isGranted ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill((isGranted ? Color.green : Color.red).opacity(0.12)))
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var settingsLinkButton: some View {
        Button {
            PermissionManager.shared.openSystemSettings(for: permission)
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Open in System Settings")
    }
}
