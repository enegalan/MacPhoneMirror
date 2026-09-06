import Foundation

// Thread-safe map of sessions, receivers, and input transports.
// Also swaps SimulatedInputTransport for Bluetooth HID when HID becomes ready.

struct OrientationUpdateResult {
    let changed: Bool
    let shouldUpdateGlobal: Bool
    let targetMissing: Bool
}

final class MirrorSessionStore: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionsByID: [String: MirrorSession] = [:]
    private var sessionReceivers: [String: ScreenMirrorReceiver] = [:]
    private var sessionTransports: [String: PhoneInputTransport] = [:]
    private var activeSessionID: String?

    var onSessionsChanged: (() -> Void)?
    var onWindowClose: ((String) -> Void)?

    var activeSession: MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        if let activeSessionID, let session = sessionsByID[activeSessionID] {
            return session
        }
        return sessionsByID.values.first
    }

    var hasActiveSessions: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !sessionsByID.isEmpty
    }

    var allSessionIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessionsByID.keys)
    }

    var sortedSessions: [MirrorSession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessionsByID.values).sorted { $0.device.name < $1.device.name }
    }

    /// Locked lookup of a session by id.
    func session(id: String) -> MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID[id]
    }

    /// Locked lookup of the video receiver for a session.
    func receiver(for sessionID: String) -> ScreenMirrorReceiver? {
        lock.lock()
        defer { lock.unlock() }
        return sessionReceivers[sessionID]
    }

    /// Returns the transport for sessionID, or the active/first transport when id is nil.
    func transport(for sessionID: String?) -> PhoneInputTransport? {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID {
            return sessionTransports[sessionID]
        }
        return activeSessionID.flatMap { sessionTransports[$0] } ?? sessionTransports.values.first
    }

    /// IDs of sessions whose connectionType is Wi-Fi (AirPlay).
    func airPlaySessionIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID.values
            .filter { $0.device.connectionType == .wifi }
            .map(\.id)
    }

    /// Arbitrary remaining session after teardown (used to restore UI state).
    func firstRemainingSession() -> MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID.values.first
    }

    /// Registers session/receiver/transport under lock; stops a previous non-AirPlay receiver if replaced.
    /// Returns whether a previous receiver was closed (caller already notified via onWindowClose).
    func install(
        session: MirrorSession,
        receiver: ScreenMirrorReceiver,
        transport: PhoneInputTransport
    ) -> Bool {
        let sessionID = session.id
        var closedPrevious = false

        lock.lock()
        if let previous = sessionReceivers[sessionID], previous !== receiver {
            let wasAirPlay = previous === NetworkStreamReceiver.shared
            Self.disconnectTransportIfOwned(sessionTransports[sessionID])
            if !wasAirPlay {
                previous.stop()
            }
            closedPrevious = true
        }
        sessionsByID[sessionID] = session
        sessionReceivers[sessionID] = receiver
        sessionTransports[sessionID] = transport
        activeSessionID = sessionID
        lock.unlock()

        if closedPrevious {
            onWindowClose?(sessionID)
        }
        onSessionsChanged?()
        return closedPrevious
    }

    /// Wi-Fi session IDs other than keepingDeviceID — tear these down before a new AirPlay session.
    func replaceAirPlaySessionIDs(keepingDeviceID: String) -> [String] {
        lock.lock()
        let existingIDs = sessionsByID.values
            .filter { $0.device.connectionType == .wifi && $0.id != keepingDeviceID }
            .map(\.id)
        lock.unlock()
        return existingIDs
    }

    /// Removes session maps; never stops the shared AirPlay receiver; may publish window close.
    func tearDown(id: String, stopReceiver: Bool, publishClose: Bool) {
        lock.lock()
        let receiver = sessionReceivers.removeValue(forKey: id)
        let transport = sessionTransports.removeValue(forKey: id)
        sessionsByID.removeValue(forKey: id)
        if activeSessionID == id {
            activeSessionID = sessionReceivers.keys.first
        }
        let isAirPlay = receiver === NetworkStreamReceiver.shared
        lock.unlock()

        Self.disconnectTransportIfOwned(transport)
        if stopReceiver, let receiver, !isAirPlay {
            receiver.stop()
        }

        onSessionsChanged?()
        if publishClose {
            onWindowClose?(id)
        }
    }

    /// Replaces the AirPlay-start SimulatedInputTransport once Bluetooth HID is ready.
    /// Only swaps if the session still holds the simulated double — avoids yanking a
    /// transport that was already set (e.g. USB path uses HID from the start).
    func replaceSimulatedTransportIfNeeded(sessionID: String, with transport: PhoneInputTransport) {
        lock.lock()
        if sessionTransports[sessionID] is SimulatedInputTransport {
            sessionTransports[sessionID] = transport
        } else if transport !== BluetoothHIDTransport.shared {
            transport.disconnect()
        }
        lock.unlock()
    }

    /// Updates orientation for a session under lock; signals whether global UI should refresh.
    func updateOrientation(_ newOrientation: DeviceOrientation, sessionID: String?) -> OrientationUpdateResult {
        lock.lock()
        let targetID = sessionID ?? activeSessionID ?? sessionsByID.keys.first
        guard let targetID, var session = sessionsByID[targetID] else {
            lock.unlock()
            return OrientationUpdateResult(changed: false, shouldUpdateGlobal: false, targetMissing: true)
        }

        let shouldUpdateGlobal = targetID == activeSessionID || sessionsByID.count == 1
        let changed = session.orientation != newOrientation
        if changed {
            session.orientation = newOrientation
            sessionsByID[targetID] = session
        }
        lock.unlock()

        if changed {
            onSessionsChanged?()
        }
        return OrientationUpdateResult(changed: changed, shouldUpdateGlobal: shouldUpdateGlobal, targetMissing: false)
    }

    /// True when the session's receiver is the shared NetworkStreamReceiver singleton.
    func isAirPlayReceiver(sessionID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionReceivers[sessionID] === NetworkStreamReceiver.shared
    }

    /// Disconnects non-shared transports; never disconnects BluetoothHIDTransport.shared.
    private static func disconnectTransportIfOwned(_ transport: PhoneInputTransport?) {
        guard let transport, transport !== BluetoothHIDTransport.shared else { return }
        transport.disconnect()
    }
}
