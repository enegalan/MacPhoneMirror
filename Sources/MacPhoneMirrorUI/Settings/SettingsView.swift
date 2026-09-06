import MacPhoneMirrorCore
import SwiftUI

// Settings tab container that hosts General / Appearance / Mirroring panes.

public struct SettingsView: View {
    @ObservedObject private var frameStyleStore = FrameStyleStore.shared

    /// Creates the Settings tab hosting General, Mirroring, and Appearance panes.
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                GeneralSettingsView()
                MirroringSettingsView()
                AppearanceSettingsView(frameStyle: $frameStyleStore.style)
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
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title2.bold())
                Text("All preferences in one place.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
