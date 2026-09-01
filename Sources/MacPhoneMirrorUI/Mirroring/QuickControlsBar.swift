import MacPhoneMirrorCore
import SwiftUI

public struct QuickControlsBar: View {
    public let onHome: () -> Void
    public let onAppSwitcher: () -> Void
    public let onControlCenter: () -> Void
    public let onNotifications: () -> Void
    public let onLock: () -> Void
    public let onScreenshot: () -> Void

    public init(
        onHome: @escaping () -> Void = {},
        onAppSwitcher: @escaping () -> Void = {},
        onControlCenter: @escaping () -> Void = {},
        onNotifications: @escaping () -> Void = {},
        onLock: @escaping () -> Void = {},
        onScreenshot: @escaping () -> Void = {}
    ) {
        self.onHome = onHome
        self.onAppSwitcher = onAppSwitcher
        self.onControlCenter = onControlCenter
        self.onNotifications = onNotifications
        self.onLock = onLock
        self.onScreenshot = onScreenshot
    }

    public var body: some View {
        HStack(spacing: 8) {
            barButton(icon: "house.fill", label: "Home", tooltip: "Go to Home Screen (⌘H)", action: onHome)
            barButton(icon: "square.2.layers.3d", label: "Apps", tooltip: "App Switcher (⌘Tab)", action: onAppSwitcher)
            barButton(icon: "switch.2", label: "Controls", tooltip: "Control Center", action: onControlCenter)
            barButton(icon: "bell.fill", label: "Notifs", tooltip: "Notification Center", action: onNotifications)

            Divider().frame(height: 18).padding(.horizontal, 4)

            barButton(icon: "camera.fill", label: "Capture", tooltip: "Take iPhone Screenshot", action: onScreenshot)
            barButton(icon: "lock.fill", label: "Lock", tooltip: "Lock / Sleep Screen", action: onLock)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
        )
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func barButton(icon: String, label: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.001))
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
