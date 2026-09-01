import MacPhoneMirrorCore
import SwiftUI

public struct HardwareButtonsView: View {
    public let frameHeight: CGFloat
    public let onActionButton: () -> Void
    public let onVolumeUp: () -> Void
    public let onVolumeDown: () -> Void
    public let onPower: () -> Void
    public let onCameraControl: () -> Void

    @State private var pressedButton: String?

    public init(
        frameHeight: CGFloat,
        onActionButton: @escaping () -> Void = {},
        onVolumeUp: @escaping () -> Void = {},
        onVolumeDown: @escaping () -> Void = {},
        onPower: @escaping () -> Void = {},
        onCameraControl: @escaping () -> Void = {}
    ) {
        self.frameHeight = frameHeight
        self.onActionButton = onActionButton
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
        self.onPower = onPower
        self.onCameraControl = onCameraControl
    }

    public var body: some View {
        ZStack {
            // Left Edge Buttons: Action Button + Volume Up + Volume Down
            HStack {
                VStack(spacing: 14) {
                    Spacer().frame(height: frameHeight * 0.16)

                    // Action Button
                    buttonPill(id: "action", height: 26, isLeft: true) {
                        onActionButton()
                    }

                    // Volume Up
                    buttonPill(id: "volUp", height: 50, isLeft: true) {
                        onVolumeUp()
                    }

                    // Volume Down
                    buttonPill(id: "volDown", height: 50, isLeft: true) {
                        onVolumeDown()
                    }

                    Spacer()
                }
                .offset(x: -3)

                Spacer()

                // Right Edge Buttons: Power Button + Camera Control
                VStack(spacing: 20) {
                    Spacer().frame(height: frameHeight * 0.20)

                    // Power / Sleep Button
                    buttonPill(id: "power", height: 75, isLeft: false) {
                        onPower()
                    }

                    Spacer().frame(height: frameHeight * 0.30)

                    // Camera Control Sapphire Glass Button (iPhone 16 Series)
                    buttonPill(id: "cameraControl", height: 44, isLeft: false, isSapphire: true) {
                        onCameraControl()
                    }

                    Spacer()
                }
                .offset(x: 3)
            }
        }
    }

    private func buttonPill(id: String, height: CGFloat, isLeft: Bool, isSapphire: Bool = false, action: @escaping () -> Void) -> some View {
        let isPressed = pressedButton == id
        return Button(action: {
            pressedButton = id
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                pressedButton = nil
            }
        }) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    isSapphire
                        ? LinearGradient(colors: [Color(white: 0.3), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(white: 0.6), Color(white: 0.4)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 4, height: height)
                .offset(x: isPressed ? (isLeft ? 2 : -2) : 0)
                .shadow(color: .black.opacity(0.3), radius: 1, x: isLeft ? -1 : 1, y: 0)
        }
        .buttonStyle(.plain)
    }
}
