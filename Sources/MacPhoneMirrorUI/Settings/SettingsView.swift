import MacPhoneMirrorCore
import SwiftUI

public struct SettingsView: View {
    @State private var selectedTab = 0
    @Binding var frameStyle: FrameRenderStyle

    public init(frameStyle: Binding<FrameRenderStyle>) {
        _frameStyle = frameStyle
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            VideoSettingsView()
                .tabItem { Label("Mirroring", systemImage: "display") }
                .tag(1)

            AppearanceSettingsView(frameStyle: $frameStyle)
                .tabItem { Label("Appearance", systemImage: "iphone") }
                .tag(2)

            InputSettingsView()
                .tabItem { Label("Input & Control", systemImage: "cursorarrow.motionlines") }
                .tag(3)
        }
        .frame(width: 520, height: 420)
        .padding(20)
    }
}

public struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoConnect") private var autoConnect = true
    @AppStorage("autoStartMirroring") private var autoStartMirroring = true

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Startup & Connection")) {
                Toggle("Launch MacPhoneMirror at Login", isOn: $launchAtLogin)
                Toggle("Automatically connect to last known iPhone", isOn: $autoConnect)
                Toggle("Automatically start screen mirroring on connect", isOn: $autoStartMirroring)
            }

            Section(header: Text("Permissions & Privacy")) {
                Button("Check System Permissions...") {
                    PermissionManager.shared.openSystemSettings(for: .cameraAndCapture)
                }
            }
        }
        .padding(16)
    }
}

public struct VideoSettingsView: View {
    @State private var selectedQuality = "Ultra (1080p / 60 FPS)"
    @State private var enableHardwareDecode = true
    @State private var lowLatencyMode = true

    public init() {}

    public var body: some View {
        Form {
            Picker("Stream Resolution", selection: $selectedQuality) {
                Text("Ultra (Native / 60 FPS)").tag("Ultra (Native / 60 FPS)")
                Text("High (1080p / 60 FPS)").tag("High (1080p / 60 FPS)")
                Text("Balanced (720p / 60 FPS)").tag("Balanced (720p / 60 FPS)")
                Text("Low Bandwidth (720p / 30 FPS)").tag("Low Bandwidth (720p / 30 FPS)")
            }

            Toggle("Hardware VideoToolbox Acceleration", isOn: $enableHardwareDecode)
            Toggle("Low-Latency Pipeline Mode", isOn: $lowLatencyMode)
        }
        .padding(16)
    }
}

public struct AppearanceSettingsView: View {
    @Binding var frameStyle: FrameRenderStyle

    public init(frameStyle: Binding<FrameRenderStyle>) {
        _frameStyle = frameStyle
    }

    public var body: some View {
        Form {
            Picker("Frame Style", selection: $frameStyle.displayMode) {
                ForEach(FrameDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if frameStyle.displayMode == .realisticFrame {
                Picker("Chassis Finish", selection: $frameStyle.finish) {
                    ForEach(FrameFinish.allCases) { finish in
                        Text(finish.rawValue).tag(finish)
                    }
                }

                Toggle("Dynamic Island / Notch Overlay", isOn: $frameStyle.showDynamicIsland)
                Toggle("Hardware Buttons (Action / Volume / Power)", isOn: $frameStyle.showHardwareButtons)
                Toggle("Chassis Reflection & Metal Specular Highlight", isOn: $frameStyle.showReflection)
                Toggle("Realistic Drop Shadow", isOn: $frameStyle.showShadow)
            }
        }
        .padding(16)
    }
}

public struct InputSettingsView: View {
    @State private var mouseSpeed: Double = 1.0
    @State private var showTouchRipples = true

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Pointer & Gestures")) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Cursor Speed")
                        Spacer()
                        Text(String(format: "%.1fx", mouseSpeed)).foregroundColor(.secondary)
                    }
                    Slider(value: $mouseSpeed, in: 0.5 ... 2.0)
                }

                Toggle("Show visual touch ripples on click", isOn: $showTouchRipples)
            }
        }
        .padding(16)
    }
}
