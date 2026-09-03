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
                        SidebarDeviceButton(
                            name: session.device.name,
                            icon: session.device.connectionType.iconName
                        ) {
                            onFocusSession(session.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarDeviceButton: View {
    let name: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(name, systemImage: icon)
                .foregroundColor(isHovered ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
