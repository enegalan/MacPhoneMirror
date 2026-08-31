import SwiftUI
import MacPhoneMirrorCore

public enum AppNavigationTab: String, CaseIterable, Identifiable {
    case mirror = "Mirroring"
    case control = "Control"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .mirror:
            return "display"
        case .control:
            return "cursorarrow.motionlines"
        case .settings:
            return "gearshape"
        }
    }
}

public struct SidebarView: View {
    @Binding var selectedTab: AppNavigationTab
    public let activeState: ConnectionState
    public let onUpgradePro: () -> Void
    
    public init(
        selectedTab: Binding<AppNavigationTab>,
        activeState: ConnectionState,
        onUpgradePro: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self.activeState = activeState
        self.onUpgradePro = onUpgradePro
    }
    
    public var body: some View {
        List(selection: $selectedTab) {
            Section("Features") {
                ForEach(AppNavigationTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            }
            
            Section("Session Status") {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(state: activeState)
                    if let dev = activeState.activeDevice {
                        Text(dev.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack {
                Divider()
                Button(action: onUpgradePro) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("MacPhoneMirror Pro")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }
}
