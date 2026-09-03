import Combine
import MacPhoneMirrorCore
import SwiftUI

public struct MainWindowView: View {
    @State private var selectedTab: AppNavigationTab = .allCases.first!
    @State private var frameStyle = FrameRenderStyle.standard

    @ObservedObject private var sessionManager = SessionManager.shared

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
                case .service:
                    ServiceView()
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
}
