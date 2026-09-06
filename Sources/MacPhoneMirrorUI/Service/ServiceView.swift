import MacPhoneMirrorCore
import SwiftUI

// AirPlay service toggle, advertised name, pairing PIN, and connected-device status.

public struct ServiceView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @ObservedObject private var pairingState = AirPlayPairingState.shared
    @State private var serviceName: String = AirPlayTXTRecordBuilder.serviceName
    @State private var isEditingName = false
    @State private var isSavingName = false
    @State private var showingConnectionGuide = false

    /// Creates the Service tab bound to the shared session and pairing state.
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                serviceCard

                if let pin = pairingState.displayPIN {
                    pairingPINCard(pin)
                }

                devicesCard
            }
            .padding(28)
        }
        .sheet(isPresented: $showingConnectionGuide) {
            PairingGuideView(initialTab: 1)
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

            Button {
                showingConnectionGuide = true
            } label: {
                Label("How to Connect", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var serviceCard: some View {
        SettingsCard(
            title: "AirPlay Service",
            subtitle: "Receiver configuration",
            icon: "antenna.radiowaves.left.and.right"
        ) {
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

            deviceNameRow
        }
        .onAppear {
            serviceName = AirPlayTXTRecordBuilder.serviceName
        }
    }

    private var deviceNameRow: some View {
        HStack(spacing: 10) {
            SettingsRowIcon("textformat", tint: .blue)
            deviceNameLabels
            Spacer()
            deviceNameEditor
            deviceNameActions
        }
        .padding(.vertical, 6)
    }

    private var deviceNameLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Device Name")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Text("The name shown in iPhone Screen Mirroring list.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var deviceNameEditor: some View {
        if isEditingName {
            TextField("Device Name", text: $serviceName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit {
                    confirmNameChange()
                }
        } else {
            Text(serviceName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var deviceNameActions: some View {
        if isEditingName {
            SubtleIconButton(systemName: "checkmark", action: confirmNameChange)
                .disabled(isSavingName)
        } else {
            SubtleIconButton(systemName: "pencil", action: beginEditing)
        }

        if isSavingName {
            ProgressView()
                .controlSize(.small)
        }
    }

    /// Enters inline edit mode for the advertised AirPlay device name.
    private func beginEditing() {
        isEditingName = true
    }

    /// Saves a trimmed device name and refreshes the advertised service name.
    private func confirmNameChange() {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newValue = trimmed
        isEditingName = false
        isSavingName = true

        Task {
            await sessionManager.updateServiceName(newValue)
            await MainActor.run {
                isSavingName = false
                serviceName = AirPlayTXTRecordBuilder.serviceName
            }
        }
    }

    /// Card that prominently displays the AirPlay pairing PIN for the user.
    private func pairingPINCard(_ pin: String) -> some View {
        SettingsCard(
            title: "AirPlay Pairing",
            subtitle: "Enter this PIN on your iPhone",
            icon: "lock.rectangle"
        ) {
            HStack(spacing: 12) {
                SettingsRowIcon("number", tint: .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text("Your iPhone is asking for a pairing code.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var devicesCard: some View {
        let sessionCount = sessionManager.sessions.count
        let subtitle = "\(sessionCount) device\(sessionCount == 1 ? "" : "s") online"
        return SettingsCard(
            title: "Connected Devices",
            subtitle: subtitle,
            icon: "iphone.and.arrow.forward"
        ) {
            if sessionManager.sessions.isEmpty {
                emptyDevicesRow
            } else {
                ForEach(sessionManager.sessions) { session in
                    connectedDeviceRow(session)
                }
            }
        }
    }

    private var emptyDevicesRow: some View {
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
    }

    /// Status row for one connected mirror session in the devices card.
    private func connectedDeviceRow(_ session: MirrorSession) -> some View {
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

private struct SubtleIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
