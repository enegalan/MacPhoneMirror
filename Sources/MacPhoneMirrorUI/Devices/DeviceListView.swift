import SwiftUI
import MacPhoneMirrorCore

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
                
                Button(action: { showingPairingGuide = true }) {
                    Label("Pairing Guide", systemImage: "questionmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
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
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "iphone")
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(device.name)
                            .font(.headline)
                        if isConnected {
                            StatusBadge(state: activeState)
                        }
                    }
                    
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
                
                Spacer()
                
                if isConnected {
                    Button(role: .destructive, action: {
                        SessionManager.shared.disconnect()
                    }) {
                        Text("Disconnect")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        onSelectDevice(device)
                    }) {
                        Text("Connect")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
