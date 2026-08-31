import SwiftUI
import MacPhoneMirrorCore

public struct ControlConfigView: View {
    @State private var enableMouseControl = true
    @State private var enableKeyboardShortcuts = true
    @State private var mouseSensitivity: Double = 1.0
    @State private var scrollInvert = false
    @State private var showingAssistiveTouchGuide = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iPhone Remote Control")
                            .font(.title2.bold())
                        Text("Configure Bluetooth HID pointer control and macOS keyboard shortcuts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("AssistiveTouch Setup Guide") {
                        showingAssistiveTouchGuide = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                MacCard {
                    Text("Input Modes")
                        .font(.headline)
                    
                    Toggle("Enable Mouse & Trackpad Pointer Control", isOn: $enableMouseControl)
                    Toggle("Enable Hardware Keyboard Shortcuts (⌘H, ⌘Tab, etc.)", isOn: $enableKeyboardShortcuts)
                    Toggle("Invert Scroll Direction", isOn: $scrollInvert)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pointer Sensitivity")
                            Spacer()
                            Text(String(format: "%.1fx", mouseSensitivity))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $mouseSensitivity, in: 0.5...2.5, step: 0.1)
                    }
                }
                
                MacCard {
                    Text("Configured iOS Shortcuts")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        ForEach(AssistiveTouchProfile.standardActions) { action in
                            HStack {
                                Label(action.title, systemImage: action.systemImage)
                                Spacer()
                                Text(action.shortcutHint)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            if action.id != AssistiveTouchProfile.standardActions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAssistiveTouchGuide) {
            AssistiveTouchGuideView()
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
                    guideStep(4, "Configure Pointer Devices", "Tap Pointer Devices > Bluetooth Devices, and choose MacPhoneMirror.")
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
