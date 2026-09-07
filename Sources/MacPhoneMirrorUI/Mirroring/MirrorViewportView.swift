import MacPhoneMirrorCore
import SwiftUI

// Full-bleed live video clipped to the iPhone screen shape; fills the mirror window.

public struct MirrorViewportView: View {
    public let sessionID: String
    public let device: PhoneDevice
    public let orientation: DeviceOrientation

    @StateObject private var metalHolder = MetalViewStateHolder()
    @State private var isDragging = false
    @State private var acceptingPointerGesture = true
    @State private var pointerGestureTask: Task<Void, Never>?
    @State private var lastMoveSentAt = Date.distantPast
    @State private var ripples: [TouchRipple] = []

    /// Creates the viewport for a device session with the given orientation.
    public init(
        sessionID: String,
        device: PhoneDevice,
        orientation: DeviceOrientation = .portrait
    ) {
        self.sessionID = sessionID
        self.device = device
        self.orientation = orientation
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = scaledCornerRadius(for: size)

            ZStack {
                Color.black

                MetalVideoView(stateHolder: metalHolder)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(pointerDragGesture(viewportSize: size))

                ForEach(ripples) { ripple in
                    Circle()
                        .stroke(Color.white.opacity(ripple.opacity), lineWidth: 2)
                        .frame(width: ripple.radius * 2, height: ripple.radius * 2)
                        .position(ripple.point)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
        }
        .background(Color.clear)
        .onAppear { bindReceiver() }
        .onChange(of: sessionID) { _, _ in bindReceiver() }
    }

    private func pointerDragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard AppPreferences.enableMouseControl else { return }
                guard acceptingPointerGesture || isDragging else { return }
                let point = value.location
                let start = value.startLocation
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
                            viewportSize: viewportSize,
                            sessionID: id
                        )
                    }

                    let now = Date()
                    guard now.timeIntervalSince(lastMoveSentAt) >= 0.016 else { return }
                    lastMoveSentAt = now
                    await SessionManager.shared.handlePointerMove(
                        at: point,
                        viewportSize: viewportSize,
                        sessionID: id
                    )
                }
            }
            .onEnded { value in
                guard AppPreferences.enableMouseControl || isDragging else { return }
                let point = value.location
                let id = sessionID
                let previous = pointerGestureTask
                pointerGestureTask = Task { @MainActor in
                    await previous?.value
                    if isDragging {
                        await SessionManager.shared.handlePointerUp(
                            at: point,
                            viewportSize: viewportSize,
                            sessionID: id
                        )
                        isDragging = false
                    }
                    lastMoveSentAt = .distantPast
                    acceptingPointerGesture = true
                }
            }
    }

    /// Spawns a fading tap-ripple animation at the pointer location when enabled.
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

    /// Binds the Metal state holder to the session's screen-mirror receiver.
    private func bindReceiver() {
        if let rec = SessionManager.shared.receiver(for: sessionID) {
            metalHolder.bind(to: rec)
        }
    }

    /// Scales the model screen corner radius to the current window size.
    private func scaledCornerRadius(for size: CGSize) -> CGFloat {
        let native = orientation.orientedSize(for: device.model.pointSize)
        let scale = min(
            size.width / max(native.width, 1),
            size.height / max(native.height, 1)
        )
        return device.model.screenCornerRadius * scale
    }
}

private struct TouchRipple: Identifiable {
    let id = UUID()
    let point: CGPoint
    var radius: CGFloat = 8
    var opacity: Double = 0.85
}
