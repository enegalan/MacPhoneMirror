import MacPhoneMirrorCore
import SwiftUI

// Frame finish / display-mode settings bound to FrameStyleStore.

public struct AppearanceSettingsView: View {
    @Binding var frameStyle: FrameRenderStyle

    /// Creates appearance settings bound to the shared frame style store.
    public init(frameStyle: Binding<FrameRenderStyle>) {
        _frameStyle = frameStyle
    }

    public var body: some View {
        SettingsCard(title: "Appearance", subtitle: "How your iPhone frame is rendered", icon: "iphone") {
            appearanceControls
        }
    }

    @ViewBuilder
    private var appearanceControls: some View {
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

    /// Selectable chassis-finish chip that updates the bound frame style.
    private func finishChip(for finish: FrameFinish) -> some View {
        let theme = FrameTheme.colors(for: finish)
        let isSelected = frameStyle.finish == finish

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                frameStyle.finish = finish
            }
        } label: {
            chipLabel(finish: finish, theme: theme, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// Label content for a finish chip: swatch, name, and selection checkmark.
    private func chipLabel(finish: FrameFinish, theme: FrameThemeColors, isSelected: Bool) -> some View {
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
}
