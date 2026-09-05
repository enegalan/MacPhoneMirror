import MacPhoneMirrorCore
import SwiftUI

public struct PairingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int

    public init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            pairingHeader
            Divider()
            tabPicker
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

    private var pairingHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("How to Connect")
                    .font(.headline)
                Text("Pick a method below and follow the steps.")
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
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("USB Cable").tag(0)
            Text("Wi-Fi").tag(1)
            Text("Mouse & Keyboard").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(16)
    }

    private var usbGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepItem(
                number: "1",
                title: "Plug in your iPhone",
                detail: "Use a USB-C or Lightning cable to connect your iPhone to this Mac."
            )
            stepItem(
                number: "2",
                title: "Trust this Mac",
                detail: "Unlock your iPhone. If you see Trust This Computer, tap Trust and enter your passcode."
            )
            stepItem(
                number: "3",
                title: "Wait for the window",
                detail: "Your iPhone screen should appear in a window on this Mac. USB is the fastest option."
            )
        }
    }

    private var wifiGuide: some View {
        let name = AirPlayTXTRecordBuilder.serviceName
        return VStack(alignment: .leading, spacing: 16) {
            stepItem(
                number: "1",
                title: "Allow the network prompt",
                detail: "If this Mac asks to use the local network, click Allow so your iPhone can find it."
            )
            stepItem(
                number: "2",
                title: "Use the same Wi-Fi",
                detail: "Connect your iPhone and this Mac to the same Wi-Fi network."
            )
            stepItem(
                number: "3",
                title: "Open Control Center",
                detail: "On iPhone, swipe down from the top-right corner of the screen."
            )
            stepItem(
                number: "4",
                title: "Tap Screen Mirroring",
                detail: "Then tap \"\(name)\" in the list. Your screen opens in a window on this Mac."
            )
            stepItem(
                number: "5",
                title: "If you don't see it",
                detail: "On this Mac, open System Settings → General → AirDrop & Handoff, "
                    + "turn off AirPlay Receiver, and try Screen Mirroring again."
            )
        }
    }

    private var bluetoothGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepItem(
                number: "1",
                title: "Turn on Bluetooth",
                detail: "Turn on Bluetooth on your iPhone and this Mac. Keep \(AppInfo.displayName) open."
            )
            stepItem(
                number: "2",
                title: "Allow Bluetooth",
                detail: "If this Mac asks to use Bluetooth, click Allow. "
                    + "You can also check System Settings → Privacy & Security → Bluetooth."
            )
            stepItem(
                number: "3",
                title: "Turn on AssistiveTouch",
                detail: "On iPhone, go to Settings → Accessibility → Touch → AssistiveTouch, and turn it on."
            )
            stepItem(
                number: "4",
                title: "Pair this Mac",
                detail: "In AssistiveTouch, tap Devices → Bluetooth Devices. "
                    + "Tap \(AppInfo.displayName) or your Mac's name. After it pairs, you can click in the mirror window."
            )
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
