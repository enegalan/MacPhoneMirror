import MacPhoneMirrorCore
import SwiftUI

public struct MirrorViewportView: View {
    public let sessionID: String
    public let device: PhoneDevice
    public let orientation: DeviceOrientation
    public let style: FrameRenderStyle

    @StateObject private var metalHolder = MetalViewStateHolder()
    @State private var isDragging = false
    @State private var acceptingPointerGesture = true
    @State private var pointerGestureTask: Task<Void, Never>?
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
            let naturalSize = naturalFrameSize
            let scale = fittedScale(naturalSize: naturalSize, in: proxy.size)
            let displaySize = CGSize(
                width: naturalSize.width * scale,
                height: naturalSize.height * scale
            )

            ZStack {
                Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()

                VStack(spacing: 4) {
                    Spacer(minLength: 0)

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
                    // scaleEffect does not change layout size; pin the layout box
                    // to the visual size so the phone stays centered and never clips.
                    .scaleEffect(scale)
                    .frame(width: displaySize.width, height: displaySize.height)

                    Spacer(minLength: 0)
                }
            }
            .onAppear { bindReceiver() }
            .onChange(of: sessionID) { _, _ in bindReceiver() }
        }
    }

    private var pointerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard acceptingPointerGesture || isDragging else { return }
                let point = value.location
                let start = value.startLocation
                let viewport = screenSize
                let id = sessionID
                let previous = pointerGestureTask
                pointerGestureTask = Task { @MainActor in
                    await previous?.value
                    if !isDragging {
                        guard acceptingPointerGesture else { return }
                        acceptingPointerGesture = false
                        isDragging = true
                        await SessionManager.shared.handlePointerDown(
                            at: start,
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
                let previous = pointerGestureTask
                pointerGestureTask = Task { @MainActor in
                    await previous?.value
                    if isDragging {
                        await SessionManager.shared.handlePointerUp(
                            at: point,
                            viewportSize: viewport,
                            sessionID: id
                        )
                        isDragging = false
                    }
                    lastMoveSentAt = .distantPast
                    acceptingPointerGesture = true
                }
            }
    }

    private func bindReceiver() {
        if let rec = SessionManager.shared.receiver(for: sessionID) {
            metalHolder.bind(to: rec)
        }
    }

    private var screenSize: CGSize {
        orientation.orientedSize(for: device.model.pointSize)
    }

    /// Unscaled outer size of `PhoneFrameView` for the current style/orientation.
    private var naturalFrameSize: CGSize {
        let oriented = orientation.orientedSize(for: device.model.pointSize)
        switch style.displayMode {
        case .borderless:
            return oriented
        case .minimalBezel:
            let inset = device.model.bezelThickness * 2
            return CGSize(width: oriented.width + inset, height: oriented.height + inset)
        case .realisticFrame:
            let inset = device.model.bezelThickness * 2 + 16
            return CGSize(width: oriented.width + inset, height: oriented.height + inset)
        }
    }

    private func fittedScale(naturalSize: CGSize, in containerSize: CGSize) -> CGFloat {
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 20

        let availableWidth = max(containerSize.width - horizontalPadding, 1)
        let availableHeight = max(containerSize.height - verticalPadding, 1)

        let fitScale = min(
            availableWidth / max(naturalSize.width, 1),
            availableHeight / max(naturalSize.height, 1)
        )
        let preferredScale = min(fitScale, 1.0) * CGFloat(style.scaleFactor)
        // Never exceed the container — landscape must shrink into a portrait-shaped window.
        return max(min(preferredScale, fitScale), 0.05)
    }
}
