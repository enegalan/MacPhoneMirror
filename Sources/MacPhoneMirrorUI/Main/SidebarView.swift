import MacPhoneMirrorCore
import SwiftUI

public enum AppNavigationTab: String, CaseIterable, Identifiable {
    case service = "Service"
    case control = "Control"
    case settings = "Settings"

    public var id: String {
        rawValue
    }

    public var icon: String {
        switch self {
        case .service:
            "airplayvideo"
        case .control:
            "cursorarrow.motionlines"
        case .settings:
            "gearshape"
        }
    }
}

public struct SidebarView: View {
    @Binding var selectedTab: AppNavigationTab
    public let activeState: ConnectionState
    public let sessions: [MirrorSession]
    public let onFocusSession: (String) -> Void

    public init(
        selectedTab: Binding<AppNavigationTab>,
        activeState: ConnectionState,
        sessions: [MirrorSession] = [],
        onFocusSession: @escaping (String) -> Void = { _ in }
    ) {
        _selectedTab = selectedTab
        self.activeState = activeState
        self.sessions = sessions
        self.onFocusSession = onFocusSession
    }

    public var body: some View {
        List(selection: $selectedTab) {
            ForEach(AppNavigationTab.allCases) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }

            if !sessions.isEmpty {
                Section("Active Devices") {
                    ForEach(sessions) { session in
                        Button {
                            onFocusSession(session.id)
                        } label: {
                            Label(session.device.name, systemImage: session.device.connectionType.iconName)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
