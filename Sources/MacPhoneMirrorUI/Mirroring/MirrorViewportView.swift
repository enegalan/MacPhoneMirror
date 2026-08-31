import SwiftUI
import MacPhoneMirrorCore

public struct MirrorViewportView: View {
    public let device: PhoneDevice
    public let orientation: DeviceOrientation
    public let style: FrameRenderStyle

    @StateObject private var metalHolder = MetalViewStateHolder()

    public init(
        device: PhoneDevice,
        orientation: DeviceOrientation = .portrait,
        style: FrameRenderStyle = .standard
    ) {
        self.device = device
        self.orientation = orientation
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    PhoneFrameView(
                        model: device.model,
                        orientation: orientation,
                        style: style
                    ) {
                        MetalVideoView(stateHolder: metalHolder)
                            .frame(width: screenSize.width, height: screenSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let point = value.location
                                        Task {
                                            await SessionManager.shared.handleMouseClick(
                                                at: point,
                                                viewportSize: screenSize
                                            )
                                        }
                                    }
                            )
                    }
                    .scaleEffect(calculatedScale(for: proxy.size))

                    Spacer()

                    QuickControlsBar(
                        onHome: { Task { try? await SessionManager.shared.sendInputEvent(.homeButton) } },
                        onAppSwitcher: { Task { try? await SessionManager.shared.sendInputEvent(.appSwitcher) } },
                        onControlCenter: { Task { try? await SessionManager.shared.sendInputEvent(.controlCenter) } },
                        onNotifications: { Task { try? await SessionManager.shared.sendInputEvent(.notificationCenter) } },
                        onLock: { Task { try? await SessionManager.shared.sendInputEvent(.lockScreen) } },
                        onScreenshot: { AppLogger.info("Screenshot taken", category: .ui) }
                    )
                    .padding(.bottom, 16)
                }
            }
            .onAppear {
                if let rec = SessionManager.shared.currentReceiver {
                    metalHolder.bind(to: rec)
                }
            }
            .onChange(of: device.id) { _, _ in
                if let rec = SessionManager.shared.currentReceiver {
                    metalHolder.bind(to: rec)
                }
            }
        }
    }

    private var screenSize: CGSize {
        orientation.isLandscape
            ? CGSize(width: device.model.pointSize.height, height: device.model.pointSize.width)
            : device.model.pointSize
    }

    private func calculatedScale(for containerSize: CGSize) -> CGFloat {
        let oriented = orientation.orientedSize(for: device.model.pointSize)

        let availableWidth = max(containerSize.width - 60, 200)
        let availableHeight = max(containerSize.height - 150, 300)

        let scaleW = availableWidth / (oriented.width + 40)
        let scaleH = availableHeight / (oriented.height + 40)

        return min(scaleW, scaleH, 1.0) * CGFloat(style.scaleFactor)
    }
}
