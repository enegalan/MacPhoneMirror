import MacPhoneMirrorCore
import SwiftUI

public struct MirrorViewportView: View {
    public let sessionID: String
    public let device: PhoneDevice
    public let orientation: DeviceOrientation
    public let style: FrameRenderStyle

    @StateObject private var metalHolder = MetalViewStateHolder()
    @State private var isDragging = false
    @State private var lastMoveSentAt = Date.distantPast

    public init(
        sessionID: String,
        device: PhoneDevice,
        orientation: DeviceOrientation = .portrait,
        style: FrameRenderStyle = .standard
    ) {
        self.sessionID = sessionID
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
                        style: style,
                        sessionID: sessionID
                    ) {
                        MetalVideoView(stateHolder: metalHolder)
                            .frame(width: screenSize.width, height: screenSize.height)
                            .contentShape(Rectangle())
                            .gesture(pointerDragGesture)
                    }
                    .scaleEffect(calculatedScale(for: proxy.size))

                    Spacer()

                    QuickControlsBar(
                        onHome: {
                            Task { try? await SessionManager.shared.sendInputEvent(.homeButton, sessionID: sessionID) }
                        },
                        onAppSwitcher: {
                            Task { try? await SessionManager.shared.sendInputEvent(.appSwitcher, sessionID: sessionID) }
                        },
                        onControlCenter: {
                            Task { try? await SessionManager.shared.sendInputEvent(.controlCenter, sessionID: sessionID) }
                        },
                        onNotifications: {
                            Task { try? await SessionManager.shared.sendInputEvent(.notificationCenter, sessionID: sessionID) }
                        },
                        onLock: {
                            Task { try? await SessionManager.shared.sendInputEvent(.lockScreen, sessionID: sessionID) }
                        },
                        onScreenshot: { AppLogger.info("Screenshot taken", category: .ui) }
                    )
                    .padding(.bottom, 16)
                }
            }
            .onAppear { bindReceiver() }
            .onChange(of: sessionID) { _, _ in bindReceiver() }
        }
    }

    private var pointerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = value.location
                let viewport = screenSize
                let id = sessionID
                Task { @MainActor in
                    if !isDragging {
                        isDragging = true
                        await SessionManager.shared.handlePointerDown(
                            at: value.startLocation,
                            viewportSize: viewport,
                            sessionID: id
                        )
                    }

                    let now = Date()
                    // ~60 Hz max — BLE HID cannot absorb every mouse pixel.
                    guard now.timeIntervalSince(lastMoveSentAt) >= 0.016 else { return }
                    lastMoveSentAt = now
                    await SessionManager.shared.handlePointerMove(
                        at: point,
                        viewportSize: viewport,
                        sessionID: id
                    )
                }
            }
            .onEnded { value in
                let point = value.location
                let viewport = screenSize
                let id = sessionID
                Task { @MainActor in
                    await SessionManager.shared.handlePointerUp(
                        at: point,
                        viewportSize: viewport,
                        sessionID: id
                    )
                    isDragging = false
                    lastMoveSentAt = .distantPast
                }
            }
    }

    private func bindReceiver() {
        if let rec = SessionManager.shared.receiver(for: sessionID) {
            metalHolder.bind(to: rec)
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
