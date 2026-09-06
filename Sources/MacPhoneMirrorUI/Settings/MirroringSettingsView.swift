import MacPhoneMirrorCore
import SwiftUI

// Stream quality, hardware decode, latency, and audio playback toggles.

public struct MirroringSettingsView: View {
    @AppStorage(AppPreferences.Key.streamQuality) private var selectedQualityRaw = StreamQuality.ultra.rawValue
    @AppStorage(AppPreferences.Key.enableHardwareDecode) private var enableHardwareDecode = true
    @AppStorage(AppPreferences.Key.lowLatencyMode) private var lowLatencyMode = true
    @AppStorage(AppPreferences.Key.enableAudioPlayback) private var enableAudioPlayback = true
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var showReconnectNotice = false

    /// Creates the Mirroring settings pane with AppStorage-backed stream prefs.
    public init() {}

    public var body: some View {
        SettingsCard(title: "Mirroring", subtitle: "Stream quality & video pipeline", icon: "display") {
            resolutionPicker
            resolutionHints
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
            ToggleRow(
                icon: "speaker.wave.2",
                tint: .purple,
                title: "AirPlay Audio Playback",
                subtitle: "Play iPhone media audio on this Mac when mirrored.",
                isOn: $enableAudioPlayback
            )
        }
        .onChange(of: selectedQualityRaw) { _, _ in
            showReconnectNotice = !sessionManager.sessions.isEmpty
        }
    }

    private var resolutionPicker: some View {
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
    }

    @ViewBuilder
    private var resolutionHints: some View {
        Text("Takes effect on the next AirPlay connection.")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.leading, 38)
            .padding(.bottom, 4)

        if showReconnectNotice {
            Text("Reconnect AirPlay to apply the new resolution.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
                .padding(.leading, 38)
                .padding(.bottom, 4)
        }
    }
}
