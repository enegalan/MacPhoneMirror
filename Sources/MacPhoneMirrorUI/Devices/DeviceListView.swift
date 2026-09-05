import MacPhoneMirrorCore
import SwiftUI

public struct DeviceListView: View {
    public let devices: [PhoneDevice]
    public let activeState: ConnectionState
    public let onSelectDevice: (PhoneDevice) -> Void
    public let onRefresh: () -> Void

    @State private var showingPairingGuide = false

    public init(
        devices: [PhoneDevice],
        activeState: ConnectionState,
        onSelectDevice: @escaping (PhoneDevice) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.devices = devices
        self.activeState = activeState
        self.onSelectDevice = onSelectDevice
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar

            if devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(devices) { device in
                            deviceRow(for: device)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingPairingGuide) {
            PairingGuideView()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discovered iPhones")
                    .font(.title2.bold())
                Text("Select a nearby device to start mirroring or control.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                Label("Scan Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: { showingPairingGuide = true }, label: {
                Label("Pairing Guide", systemImage: "questionmark.circle")
            })
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No iPhones Discovered")
                .font(.headline)
            Text("Connect your iPhone via USB cable or ensure both devices are on the same Wi-Fi network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Scan for Devices", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deviceRow(for device: PhoneDevice) -> some View {
        let isConnected = activeState.activeDevice?.id == device.id

        return MacCard {
            deviceRowContent(device: device, isConnected: isConnected)
        }
    }

    private func deviceRowContent(device: PhoneDevice, isConnected: Bool) -> some View {
        HStack(spacing: 16) {
            deviceIcon
            deviceMetadata(device)
            Spacer()
            deviceActionButton(device: device, isConnected: isConnected)
        }
    }

    private var deviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 48, height: 48)
            Image(systemName: "iphone")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
        }
    }

    private func deviceMetadata(_ device: PhoneDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.name)
                .font(.headline)

            HStack(spacing: 12) {
                Label(device.model.rawValue, systemImage: "info.circle")
                Label(device.connectionType.rawValue, systemImage: device.connectionType.iconName)
                if let battery = device.batteryLevel {
                    Label("\(Int(battery * 100))%", systemImage: "battery.75")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func deviceActionButton(device: PhoneDevice, isConnected: Bool) -> some View {
        if isConnected {
            Button(
                role: .destructive,
                action: {
                    SessionManager.shared.disconnect()
                },
                label: {
                    Text("Disconnect")
                }
            )
            .buttonStyle(.bordered)
        } else {
            Button(
                action: {
                    onSelectDevice(device)
                },
                label: {
                    Text("Connect")
                }
            )
            .buttonStyle(.borderedProminent)
        }
    }
}
