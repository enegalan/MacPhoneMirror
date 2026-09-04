import MacPhoneMirrorCore
import SwiftUI

public struct SettingsView: View {
    @Binding var frameStyle: FrameRenderStyle

    public init(frameStyle: Binding<FrameRenderStyle>) {
        _frameStyle = frameStyle
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                GeneralSettingsView()
                MirroringSettingsView()
                AppearanceSettingsView(frameStyle: $frameStyle)
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title2.bold())
                Text("All preferences in one place.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

public struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoStartMirroring") private var autoStartMirroring = true
    @State private var hovering = false

    public init() {}

    public var body: some View {
        SettingsCard(title: "General", subtitle: "Startup & connection behavior", icon: "gearshape") {
            ToggleRow(
                icon: "power",
                tint: .orange,
                title: "Launch \(AppInfo.displayName) at Login",
                subtitle: "Start automatically whenever you log in to this Mac.",
                isOn: $launchAtLogin
            )
            ToggleRow(
                icon: "play.rectangle",
                tint: .green,
                title: "Auto-start screen mirroring on connect",
                subtitle: "Begin mirroring as soon as a device connects.",
                isOn: $autoStartMirroring
            )

            SettingsDivider()

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SystemPermission.allCases) { permission in
                    PermissionStatusRow(permission: permission)
                        .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct PermissionStatusRow: View {
    let permission: SystemPermission
    @State private var status: Bool?
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

            VStack(alignment: .leading, spacing: 1) {
                Text(permission.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(permission.reasonDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let granted = status {
                Text(granted ? "Granted" : "Not Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(granted ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((granted ? Color.green : Color.red).opacity(0.12)))
            } else {
                ProgressView()
                    .controlSize(.small)
            }

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
            status = PermissionManager.shared.checkPermissionStatus(permission)
        }
    }
}

public struct MirroringSettingsView: View {
    @AppStorage("streamQuality") private var selectedQualityRaw = StreamQuality.ultra.rawValue
    @State private var enableHardwareDecode = true
    @State private var lowLatencyMode = true

    public init() {}

    public var body: some View {
        SettingsCard(title: "Mirroring", subtitle: "Stream quality & video pipeline", icon: "display") {
            SettingsPickerRow(
                icon: "rectangle.compress.vertical",
                tint: .blue,
                title: "Stream Resolution"
            ) {
                Picker("Stream Resolution", selection: $selectedQualityRaw) {
                    ForEach(StreamQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            ToggleRow(
                icon: "cpu",
                tint: .teal,
                title: "Hardware VideoToolbox Acceleration",
                subtitle: "Use the GPU for decoding to reduce CPU usage.",
                isOn: $enableHardwareDecode
            )
            ToggleRow(
                icon: "bolt",
                tint: .yellow,
                title: "Low-Latency Pipeline Mode",
                subtitle: "Prioritize responsiveness over buffering.",
                isOn: $lowLatencyMode
            )
        }
    }
}

public struct AppearanceSettingsView: View {
    @Binding var frameStyle: FrameRenderStyle

    public init(frameStyle: Binding<FrameRenderStyle>) {
        _frameStyle = frameStyle
    }

    public var body: some View {
        SettingsCard(title: "Appearance", subtitle: "How your iPhone frame is rendered", icon: "iphone") {
            SettingsPickerRow(
                icon: "square.3.layers.3d",
                tint: .indigo,
                title: "Frame Style"
            ) {
                Picker("Frame Style", selection: $frameStyle.displayMode) {
                    ForEach(FrameDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if frameStyle.displayMode == .realisticFrame {
                FinishPickerView(frameStyle: $frameStyle)

                ToggleRow(
                    icon: "button.programmable",
                    tint: .green,
                    title: "Hardware Buttons",
                    subtitle: "Action button, volume and side power button.",
                    isOn: $frameStyle.showHardwareButtons
                )
                ToggleRow(
                    icon: "sun.max",
                    tint: .orange,
                    title: "Chassis Reflection",
                    subtitle: "Realistic metal specular highlight.",
                    isOn: $frameStyle.showReflection
                )
                ToggleRow(
                    icon: "circle.lefthalf.filled",
                    tint: .purple,
                    title: "Realistic Drop Shadow",
                    subtitle: "Soft shadow beneath the device.",
                    isOn: $frameStyle.showShadow
                )
            }
        }
    }
}

private struct FinishPickerView: View {
    @Binding var frameStyle: FrameRenderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsRowIcon("paintpalette", tint: .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chassis Finish")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Choose the metal finish of your phone frame.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(FrameFinish.allCases) { finish in
                    finishChip(for: finish)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func finishChip(for finish: FrameFinish) -> some View {
        let theme = FrameTheme.colors(for: finish)
        let isSelected = frameStyle.finish == finish

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                frameStyle.finish = finish
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: theme.metalGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )

                Text(finish.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Components

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let content: Content
    @State private var isHovered = false

    init(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsSectionHeaderIcon(icon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct SettingsSectionHeaderIcon: View {
    let systemName: String

    init(_ systemName: String) {
        self.systemName = systemName
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
        }
    }
}

struct SettingsRowIcon: View {
    let systemName: String
    let tint: Color

    init(_ systemName: String, tint: Color) {
        self.systemName = systemName
        self.tint = tint
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint)
        }
    }
}

struct ToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                SettingsRowIcon(icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .padding(.vertical, 6)
    }
}

struct SettingsPickerRow<PickerContent: View>: View {
    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder let content: PickerContent

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowIcon(icon, tint: tint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            content
        }
        .padding(.vertical, 6)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 4)
    }
}
