import MacPhoneMirrorCore
import SwiftUI

public struct ControlConfigView: View {
    @State private var enableMouseControl = true
    @State private var enableKeyboardShortcuts = true
    @State private var mouseSensitivity: Double = 1.0
    @State private var scrollInvert = false
    @State private var showTouchRipples = true
    @State private var showingAssistiveTouchGuide = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                SettingsCard(title: "Input Modes", subtitle: "Bluetooth HID pointer control & keyboard shortcuts", icon: "cursorarrow.motionlines") {
                    ToggleRow(
                        icon: "cursorarrow.click",
                        tint: .blue,
                        title: "Mouse & Trackpad Pointer Control",
                        subtitle: "Move the pointer and click on your iPhone's screen.",
                        isOn: $enableMouseControl
                    )
                    ToggleRow(
                        icon: "keyboard",
                        tint: .indigo,
                        title: "Hardware Keyboard Shortcuts",
                        subtitle: "⌘H home, ⌘Tab app switcher, Esc lock screen.",
                        isOn: $enableKeyboardShortcuts
                    )
                    ToggleRow(
                        icon: "arrow.up.and.down",
                        tint: .teal,
                        title: "Invert Scroll Direction",
                        subtitle: "Reverse the scroll wheel direction on device.",
                        isOn: $scrollInvert
                    )
                    ToggleRow(
                        icon: "water.waves",
                        tint: .cyan,
                        title: "Visual Touch Ripples",
                        subtitle: "Animate a tap indicator whenever you click on the screen.",
                        isOn: $showTouchRipples
                    )
                }

                SettingsCard(title: "Pointer Sensitivity", subtitle: "How quickly the cursor moves across your iPhone", icon: "cursorarrow.rays") {
                    HStack(spacing: 10) {
                        SettingsRowIcon("gauge.with.dots.needle.50percent", tint: .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sensitivity")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Tune how fast the pointer travels relative to your trackpad.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1fx", mouseSensitivity))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }

                    Slider(value: $mouseSensitivity, in: 0.5 ... 2.5, step: 0.1)
                        .tint(.accentColor)
                        .padding(.top, 6)
                }

                SettingsCard(title: "Configured iOS Shortcuts", subtitle: "Actions mapped to AssistiveTouch and keyboard", icon: "sparkles.rectangle.stack") {
                    VStack(spacing: 0) {
                        ForEach(AssistiveTouchProfile.standardActions) { action in
                            HStack(spacing: 12) {
                                SettingsRowIcon(action.systemImage, tint: .accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(action.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(action.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(action.shortcutHint)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                            .padding(.vertical, 8)

                            if action.id != AssistiveTouchProfile.standardActions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showingAssistiveTouchGuide) {
            AssistiveTouchGuideView()
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
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone Remote Control")
                    .font(.title2.bold())
                Text("Configure Bluetooth HID pointer control and macOS keyboard shortcuts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingAssistiveTouchGuide = true
            } label: {
                Label("AssistiveTouch Guide", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

public struct AssistiveTouchGuideView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Configuring iOS AssistiveTouch")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Apple's iOS Security Model strictly forbids external apps from injecting touches without user-approved accessibility pointer devices. Follow these steps:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    guideStep(1, "Open iOS Settings", "On your iPhone, open the standard Settings app.")
                    guideStep(2, "Navigate to Accessibility", "Tap Accessibility > Touch > AssistiveTouch.")
                    guideStep(3, "Enable AssistiveTouch", "Turn the main toggle ON. You will see the circular touch button.")
                    guideStep(4, "Configure Pointer Devices", "Tap Pointer Devices > Bluetooth Devices, and choose \(AppInfo.displayName).")
                    guideStep(5, "Enjoy Full Control", "You can now click, drag, scroll, type, and navigate your iPhone smoothly from your Mac!")
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 440)
    }

    private func guideStep(_ num: Int, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(num)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}
