import Combine
import MacPhoneMirrorCore
import SwiftUI

public struct MainWindowView: View {
    @State private var selectedTab: AppNavigationTab = .mirror
    @State private var frameStyle = FrameRenderStyle.standard
    @State private var showPairingGuide = false

    @ObservedObject private var sessionManager = SessionManager.shared
    @ObservedObject private var pairingState = AirPlayPairingState.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTab: $selectedTab,
                activeState: sessionManager.state,
                sessions: sessionManager.sessions,
                onFocusSession: { sessionID in
                    openWindow(id: MirrorWindowID.session, value: sessionID)
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            Group {
                switch selectedTab {
                case .mirror:
                    hubMirrorContent
                case .control:
                    ControlConfigView()
                case .settings:
                    SettingsView(frameStyle: $frameStyle)
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if !sessionManager.sessions.isEmpty {
                        Button(role: .destructive, action: { sessionManager.disconnect() }) {
                            Label("Stop All", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPairingGuide) {
            PairingGuideView()
        }
        .onAppear {
            for session in sessionManager.sessions {
                openWindow(id: MirrorWindowID.session, value: session.id)
            }
        }
        .onReceive(sessionManager.sessionWindowOpenPublisher) { sessionID in
            openWindow(id: MirrorWindowID.session, value: sessionID)
        }
        .onReceive(sessionManager.sessionWindowClosePublisher) { sessionID in
            dismissWindow(id: MirrorWindowID.session, value: sessionID)
        }
    }

    @ViewBuilder
    private var hubMirrorContent: some View {
        if case let .failed(message) = sessionManager.state {
            connectionErrorView(message: message)
        } else {
            waitingForAirPlayView
        }
    }

    private var waitingForAirPlayView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 96, height: 96)
                Image(systemName: "airplayvideo")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Waiting for iPhone")
                    .font(.title2.bold())
                Text("On your iPhone, open Control Center → Screen Mirroring → \(AppInfo.displayName).\nEach connected device opens in its own window.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            StatusBadge(state: sessionManager.state)

            if !sessionManager.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active devices")
                        .font(.headline)
                    ForEach(sessionManager.sessions) { session in
                        Button {
                            openWindow(id: MirrorWindowID.session, value: session.id)
                        } label: {
                            Label(session.device.name, systemImage: "iphone")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }

            if let pin = pairingState.displayPIN {
                VStack(spacing: 8) {
                    Text("AirPlay PIN")
                        .font(.headline)
                    Text(pin)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Text("Enter this code on your iPhone if prompted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }

            Button("Connection Help") {
                showPairingGuide = true
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectionErrorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("AirPlay Receiver Error")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await sessionManager.startListening() }
                }
                .buttonStyle(.borderedProminent)
                Button("Help") {
                    showPairingGuide = true
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
