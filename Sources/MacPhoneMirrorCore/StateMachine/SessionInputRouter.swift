import CoreGraphics
import Foundation

// Converts viewport pointer events into PhoneInputEvents via InputCoordinateMapper,
// then forwards them through SessionManager.sendInputEvent.

struct SessionInputRouter {
    private let coordinateMapper: InputCoordinateMapper
    private let sessionLookup: (String) -> MirrorSession?
    private let activeSessionID: () -> String?
    private let send: (PhoneInputEvent, String?) async throws -> Void

    /// Injects mapper and session/send closures so SessionManager stays testable.
    init(
        coordinateMapper: InputCoordinateMapper = StandardCoordinateMapper(),
        sessionLookup: @escaping (String) -> MirrorSession?,
        activeSessionID: @escaping () -> String?,
        send: @escaping (PhoneInputEvent, String?) async throws -> Void
    ) {
        self.coordinateMapper = coordinateMapper
        self.sessionLookup = sessionLookup
        self.activeSessionID = activeSessionID
        self.send = send
    }

    /// Moves then presses left button in normalized device space when mouse control is on.
    func handlePointerDown(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String?
    ) async {
        guard AppPreferences.enableMouseControl else { return }
        guard let sessionID = resolvedSessionID(sessionID),
              let normPoint = normalizedPoint(viewportPoint, viewportSize: viewportSize, sessionID: sessionID)
        else { return }

        try? await send(.pointerTo(normalizedX: normPoint.x, normalizedY: normPoint.y), sessionID)
        try? await send(.pointerDown(button: .left), sessionID)
    }

    /// Relays pointer motion as normalized pointerTo events when mouse control is on.
    func handlePointerMove(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String?
    ) async {
        guard AppPreferences.enableMouseControl else { return }
        guard let sessionID = resolvedSessionID(sessionID),
              let normPoint = normalizedPoint(viewportPoint, viewportSize: viewportSize, sessionID: sessionID)
        else { return }

        try? await send(.pointerTo(normalizedX: normPoint.x, normalizedY: normPoint.y), sessionID)
    }

    /// Moves (if mappable) then releases left button when mouse control is on.
    func handlePointerUp(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String?
    ) async {
        guard AppPreferences.enableMouseControl else { return }
        guard let sessionID = resolvedSessionID(sessionID) else { return }

        if let normPoint = normalizedPoint(viewportPoint, viewportSize: viewportSize, sessionID: sessionID) {
            try? await send(.pointerTo(normalizedX: normPoint.x, normalizedY: normPoint.y), sessionID)
        }
        try? await send(.pointerUp(button: .left), sessionID)
    }

    /// Prefers an existing session id; falls back to active only when the argument is nil.
    private func resolvedSessionID(_ sessionID: String?) -> String? {
        if let sessionID, sessionLookup(sessionID) != nil {
            return sessionID
        }
        return sessionID == nil ? activeSessionID() : nil
    }

    /// Maps viewport coordinates into device-normalized space for the session's model/orientation.
    private func normalizedPoint(
        _ viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String
    ) -> CGPoint? {
        guard let session = sessionLookup(sessionID) else { return nil }
        return coordinateMapper.map(
            point: viewportPoint,
            in: viewportSize,
            device: session.device,
            orientation: session.orientation
        )
    }
}
