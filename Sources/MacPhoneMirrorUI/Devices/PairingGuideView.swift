import MacPhoneMirrorCore
import SwiftUI

public struct PairingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection & Pairing Guide")
                        .font(.headline)
                    Text("Follow these steps to connect your iPhone to \(AppInfo.displayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            Picker("", selection: $selectedTab) {
                Text("USB Connection (Recommended)").tag(0)
                Text("Wi-Fi / AirPlay").tag(1)
                Text("Bluetooth Control Setup").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedTab == 0 {
                        usbGuide
                    } else if selectedTab == 1 {
                        wifiGuide
                    } else {
                        bluetoothGuide
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 580, height: 480)
    }

    private var usbGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepItem(number: "1", title: "Connect via USB-C or Lightning Cable", detail: "Plug your iPhone directly into your Mac using an Apple certified data cable.")
            stepItem(number: "2", title: "Trust This Computer", detail: "Unlock your iPhone. If prompted, tap 'Trust This Computer' and enter your passcode.")
            stepItem(number: "3", title: "Hardware-Accelerated Zero Lag Mirroring", detail: "\(AppInfo.displayName) uses native AVFoundation USB capture to deliver 60 FPS video at sub-10ms latency.")
        }
    }

    private var wifiGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            // swiftlint:disable:next line_length
            stepItem(number: "1", title: "Allow Local Network Access", detail: "When macOS prompts, allow \(AppInfo.displayName) to use the local network. Without this, your iPhone cannot discover the AirPlay receiver.")
            stepItem(number: "2", title: "Same Wi-Fi Network", detail: "Ensure both your Mac and iPhone are connected to the same Wi-Fi network.")
            stepItem(number: "3", title: "Open Control Center on iPhone", detail: "Swipe down from the top right corner of your iPhone screen to open Control Center.")
            stepItem(number: "4", title: "Tap Screen Mirroring", detail: "Select '\(AppInfo.displayName)' from the list of available AirPlay receivers.")
            // swiftlint:disable:next line_length
            stepItem(number: "5", title: "AirPlay Receiver Conflict", detail: "If \(AppInfo.displayName) does not appear, disable macOS AirPlay Receiver in System Settings > General > AirDrop & Handoff > AirPlay Receiver.")
        }
    }

    private var bluetoothGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepItem(number: "1", title: "Enable Bluetooth on Mac & iPhone", detail: "Make sure Bluetooth is powered on in macOS and iOS Settings.")
            stepItem(number: "2", title: "Enable AssistiveTouch on iPhone", detail: "On iPhone, go to Settings > Accessibility > Touch > AssistiveTouch and toggle it ON.")
            stepItem(number: "3", title: "Pair Pointer Device", detail: "In Settings > Accessibility > Touch > AssistiveTouch > Devices > Bluetooth Devices, select \(AppInfo.displayName) to pair.")
        }
    }

    private func stepItem(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
