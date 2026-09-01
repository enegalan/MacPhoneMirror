import SwiftUI
import MacPhoneMirrorCore

public struct PhoneFrameView<ScreenContent: View>: View {
    public let model: PhoneModel
    public let orientation: DeviceOrientation
    public let style: FrameRenderStyle
    public let sessionID: String?
    public let screenContent: ScreenContent

    public init(
        model: PhoneModel = .iPhone16Pro,
        orientation: DeviceOrientation = .portrait,
        style: FrameRenderStyle = .standard,
        sessionID: String? = nil,
        @ViewBuilder screenContent: () -> ScreenContent
    ) {
        self.model = model
        self.orientation = orientation
        self.style = style
        self.sessionID = sessionID
        self.screenContent = screenContent()
    }

    private var orientedScreenSize: CGSize {
        orientation.orientedSize(for: model.pointSize)
    }

    private var chassisSize: CGSize {
        CGSize(
            width: orientedScreenSize.width + model.bezelThickness * 2,
            height: orientedScreenSize.height + model.bezelThickness * 2
        )
    }

    private var theme: (outerBorder: Color, innerBezel: Color, metalGradient: Gradient) {
        FrameTheme.colors(for: style.finish)
    }

    public var body: some View {
        Group {
            switch style.displayMode {
            case .borderless:
                screenContainer
            case .minimalBezel:
                minimalBezelContainer
            case .realisticFrame:
                realisticFrameContainer
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: orientation)
    }

    private var screenContainer: some View {
        ZStack {
            screenContent
                .frame(width: orientedScreenSize.width, height: orientedScreenSize.height)

            if style.showDynamicIsland && orientation.isPortrait {
                VStack {
                    DynamicIslandView(model: model)
                        .padding(.top, 11)
                    Spacer(minLength: 0)
                }
                .frame(width: orientedScreenSize.width, height: orientedScreenSize.height)
            }
        }
        .frame(width: orientedScreenSize.width, height: orientedScreenSize.height)
        .clipShape(RoundedRectangle(cornerRadius: model.screenCornerRadius, style: .continuous))
    }

    private var minimalBezelContainer: some View {
        screenContainer
            .padding(model.bezelThickness)
            .background(
                RoundedRectangle(cornerRadius: model.outerCornerRadius, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: model.outerCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: style.showShadow ? .black.opacity(0.35) : .clear, radius: 24, x: 0, y: 12)
    }

    private var realisticFrameContainer: some View {
        let outerSize = CGSize(width: chassisSize.width + 16, height: chassisSize.height + 16)

        return ZStack {
            if style.showHardwareButtons && orientation.isPortrait {
                HardwareButtonsView(
                    frameHeight: chassisSize.height + 16,
                    onActionButton: {
                        Task { try? await SessionManager.shared.sendInputEvent(.siri, sessionID: sessionID) }
                    },
                    onVolumeUp: {
                        Task { try? await SessionManager.shared.sendInputEvent(.volumeUp, sessionID: sessionID) }
                    },
                    onVolumeDown: {
                        Task { try? await SessionManager.shared.sendInputEvent(.volumeDown, sessionID: sessionID) }
                    },
                    onPower: {
                        Task { try? await SessionManager.shared.sendInputEvent(.lockScreen, sessionID: sessionID) }
                    },
                    onCameraControl: {
                        AppLogger.info("Camera control triggered", category: .input)
                    }
                )
                .frame(width: outerSize.width, height: outerSize.height)
            }

            RoundedRectangle(cornerRadius: model.outerCornerRadius + 2, style: .continuous)
                .fill(LinearGradient(gradient: theme.metalGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: outerSize.width, height: outerSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: model.outerCornerRadius + 2, style: .continuous)
                        .stroke(Color.white.opacity(style.showReflection ? 0.35 : 0.0), lineWidth: 1.2)
                )

            RoundedRectangle(cornerRadius: model.outerCornerRadius, style: .continuous)
                .fill(theme.innerBezel)
                .frame(width: chassisSize.width, height: chassisSize.height)

            screenContainer
        }
        .frame(width: outerSize.width, height: outerSize.height)
        .shadow(color: style.showShadow ? Color.black.opacity(0.45) : .clear, radius: 36, x: 0, y: 18)
    }
}
