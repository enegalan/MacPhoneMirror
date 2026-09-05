import MacPhoneMirrorCore
import SwiftUI

public struct ControlConfigView: View {
    @AppStorage(AppPreferences.Key.enableMouseControl) private var enableMouseControl = true
    @AppStorage(AppPreferences.Key.mouseSensitivity) private var mouseSensitivity = 1.0
    @AppStorage(AppPreferences.Key.showTouchRipples) private var showTouchRipples = true
    @State private var showingAssistiveTouchGuide = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                inputModesCard
                sensitivityCard
            }
            .padding(28)
        }
        .sheet(isPresented: $showingAssistiveTouchGuide) {
            AssistiveTouchGuideView()
        }
    }

    private var inputModesCard: some View {
        SettingsCard(
            title: "Input Modes",
            subtitle: "Bluetooth HID pointer control",
            icon: "cursorarrow.motionlines"
        ) {
            ToggleRow(
                icon: "cursorarrow.click",
                tint: .blue,
                title: "Mouse & Trackpad Pointer Control",
                subtitle: "Move the pointer and click on your iPhone's screen.",
                isOn: $enableMouseControl
            )
            ToggleRow(
                icon: "water.waves",
                tint: .cyan,
                title: "Visual Touch Ripples",
                subtitle: "Animate a tap indicator whenever you click on the screen.",
                isOn: $showTouchRipples
            )
        }
    }

    private var sensitivityCard: some View {
        SettingsCard(
            title: "Pointer Sensitivity",
            subtitle: "How quickly the cursor moves across your iPhone",
            icon: "cursorarrow.rays"
        ) {
            HStack(spacing: 10) {
                SettingsRowIcon("gauge.with.dots.needle.50percent", tint: .pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sensitivity")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Tune how fast relative pointer travel feels.")
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
                Text("Configure Bluetooth HID pointer control from this Mac.")
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
            assistiveTouchHeader
            Divider()
            assistiveTouchSteps
        }
        .frame(width: 540, height: 440)
    }

    private var assistiveTouchHeader: some View {
        HStack {
            Text("Set up AssistiveTouch")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private var assistiveTouchSteps: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("To click and drag on your iPhone from this Mac, turn on AssistiveTouch and pair this Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                guideStep(1, "Open Settings on iPhone", "Open the Settings app on your iPhone.")
                guideStep(2, "Go to AssistiveTouch", "Tap Accessibility → Touch → AssistiveTouch.")
                guideStep(
                    3,
                    "Turn it on",
                    "Turn on AssistiveTouch. A small circle appears on the screen."
                )
                guideStep(
                    4,
                    "Pair this Mac",
                    "Keep \(AppInfo.displayName) open. Tap Devices → Bluetooth Devices, "
                        + "then tap \(AppInfo.displayName) or your Mac's name."
                )
                guideStep(
                    5,
                    "Start using it",
                    "You can now click and drag on your iPhone from this Mac."
                )
            }
            .padding(24)
        }
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
