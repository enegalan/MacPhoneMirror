import Foundation

// No-op PhoneInputTransport used as (1) unit-test double and (2) AirPlay fallback
// while Bluetooth HID is still starting or unavailable.
// Records lastEvent/sentEventsCount for tests; does not reach the iPhone.
// SessionManager replaces it via MirrorSessionStore.replaceSimulatedTransportIfNeeded once HID connects.

public final class SimulatedInputTransport: PhoneInputTransport, @unchecked Sendable {
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    public var transportName: String {
        "Simulated Input Transport"
    }

    private var _isConnected: Bool = true
    private let lock = NSLock()
    public var lastEvent: PhoneInputEvent?
    public var sentEventsCount: Int = 0

    /// Creates a connected-by-default simulated transport for tests and HID fallback.
    public init() {}

    /// Marks the transport connected (no network or Bluetooth work).
    public func connect() async throws {
        setConnected(true)
    }

    /// Marks the transport disconnected for tests that assert connection state.
    public func disconnect() {
        setConnected(false)
    }

    /// Thread-safe update of the simulated connection flag.
    private func setConnected(_ connected: Bool) {
        lock.lock()
        _isConnected = connected
        lock.unlock()
    }

    /// Records the event for tests and logs it; never reaches a physical phone.
    public func send(_ event: PhoneInputEvent) async throws {
        recordEvent(event)
        AppLogger.debug("Simulated input event received: \(event)", category: .input)
    }

    /// Stores `lastEvent` and increments `sentEventsCount` under the lock.
    private func recordEvent(_ event: PhoneInputEvent) {
        lock.lock()
        lastEvent = event
        sentEventsCount += 1
        lock.unlock()
    }
}
