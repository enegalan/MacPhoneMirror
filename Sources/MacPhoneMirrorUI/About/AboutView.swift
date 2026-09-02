import MacPhoneMirrorCore
import SwiftUI

public struct AboutView: View {
    private let logo: Image?

    public init(logo: Image? = nil) {
        self.logo = logo
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if let logo {
                    logo
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                } else {
                    Image(systemName: "display")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                        .frame(width: 128, height: 128)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
            }
            .padding(.bottom, 20)

            Text(AppInfo.displayName)
                .font(.title2.bold())

            Text("Version \(AppInfo.version)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Spacer()

            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .frame(width: 320, height: 340)
    }
}
