import SwiftUI

// Shared Settings section chrome so General/Mirroring panes look consistent.

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let content: Content
    @State private var isHovered = false

    /// Builds a titled settings section card with SF Symbol header and content.
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

    /// Accent-tinted header glyph for a settings card title row.
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

    /// Compact tinted row icon used beside settings labels.
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
