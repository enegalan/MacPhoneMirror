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
    @State private var ripples: [TouchRipple] = []

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
            viewportContent(in: proxy.size)
        }
    }

    private func viewportContent(in containerSize: CGSize) -> some View {
        let naturalSize = naturalFrameSize
        let scale = fittedScale(naturalSize: naturalSize, in: containerSize)
        let displaySize = CGSize(
            width: naturalSize.width * scale,
            height: naturalSize.height * scale
        )

        return ZStack {
            Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()

            VStack(spacing: 4) {
                Spacer(minLength: 0)
                phoneFrame(scale: scale, displaySize: displaySize)
                Spacer(minLength: 0)
            }
        }
        .onAppear { bindReceiver() }
        .onChange(of: sessionID) { _, _ in bindReceiver() }
    }

    private func phoneFrame(scale: CGFloat, displaySize: CGSize) -> some View {
        PhoneFrameView(
            model: device.model,
            orientation: orientation,
            style: style,
            sessionID: sessionID
        ) {
            ZStack {
                MetalVideoView(stateHolder: metalHolder)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .contentShape(Rectangle())
                    .gesture(pointerDragGesture)

                ForEach(ripples) { ripple in
                    Circle()
                        .stroke(Color.white.opacity(ripple.opacity), lineWidth: 2)
                        .frame(width: ripple.radius * 2, height: ripple.radius * 2)
                        .position(ripple.point)
                        .allowsHitTesting(false)
                }
            }
        }
        .scaleEffect(scale)
        .frame(width: displaySize.width, height: displaySize.height)
    }

    private var pointerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard AppPreferences.enableMouseControl else { return }
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
                        spawnRipple(at: start)
                        await SessionManager.shared.handlePointerDown(
                            at: start,
                            viewportSize: viewport,
                            sessionID: id
                        )
                    }

                    let now = Date()
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
                guard AppPreferences.enableMouseControl || isDragging else { return }
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

    private func spawnRipple(at point: CGPoint) {
        guard AppPreferences.showTouchRipples else { return }
        let ripple = TouchRipple(point: point)
        ripples.append(ripple)
        withAnimation(.easeOut(duration: 0.45)) {
            if let index = ripples.firstIndex(where: { $0.id == ripple.id }) {
                ripples[index].radius = 36
                ripples[index].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ripples.removeAll { $0.id == ripple.id }
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
        return max(min(preferredScale, fitScale), 0.05)
    }
}

private struct TouchRipple: Identifiable {
    let id = UUID()
    let point: CGPoint
    var radius: CGFloat = 8
    var opacity: Double = 0.85
}
