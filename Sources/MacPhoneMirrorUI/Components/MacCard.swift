import SwiftUI

public struct MacCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

public struct QuickActionButton: View {
    public let title: String
    public let icon: String
    public let shortcut: String?
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(title: String, icon: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .primary)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.06))
                        )
                }
            }
            .frame(width: 64, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
