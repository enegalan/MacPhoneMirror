import MacPhoneMirrorCore
import SwiftUI

public struct ServiceView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var serviceName: String = AirPlayTXTRecordBuilder.serviceName
    @State private var serviceNameDebounceTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                serviceCard
                devicesCard
            }
            .padding(28)
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
                Image(systemName: "airplayvideo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Service")
                    .font(.title2.bold())
                Text("AirPlay receiver & connected devices.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var serviceCard: some View {
        SettingsCard(title: "AirPlay Service", subtitle: "Receiver configuration", icon: "antenna.radiowaves.left.and.right") {
            ToggleRow(
                icon: "power",
                tint: .green,
                title: "Enable AirPlay Service",
                subtitle: "Advertise this Mac as an AirPlay receiver for iPhone screen mirroring.",
                isOn: Binding(
                    get: { sessionManager.isServiceEnabled },
                    set: { sessionManager.setServiceEnabled($0) }
                )
            )

            SettingsDivider()

            HStack(spacing: 10) {
                SettingsRowIcon("textformat", tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device Name")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("The name shown in iPhone Screen Mirroring list.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                TextField("Device Name", text: $serviceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onChange(of: serviceName) { _, newValue in
                        serviceNameDebounceTask?.cancel()
                        serviceNameDebounceTask = Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            guard !Task.isCancelled else { return }
                            await sessionManager.updateServiceName(newValue)
                        }
                    }
            }
            .padding(.vertical, 6)
        }
        .onAppear {
            serviceName = AirPlayTXTRecordBuilder.serviceName
        }
    }

    private var devicesCard: some View {
        SettingsCard(title: "Connected Devices", subtitle: "\(sessionManager.sessions.count) device\(sessionManager.sessions.count == 1 ? "" : "s") online", icon: "iphone.and.arrow.forward") {
            if sessionManager.sessions.isEmpty {
                HStack(spacing: 10) {
                    SettingsRowIcon("wifi.slash", tint: .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No devices connected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Open Control Center → Screen Mirroring on your iPhone.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                ForEach(sessionManager.sessions) { session in
                    HStack(spacing: 10) {
                        SettingsRowIcon(session.device.connectionType.iconName, tint: .blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.device.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text(session.device.connectionType.rawValue)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }
            }
        }
    }
}
