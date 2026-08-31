import Foundation

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
    
    public init() {}
    
    public func connect() async throws {
        setConnected(true)
    }
    
    public func disconnect() {
        setConnected(false)
    }
    
    private func setConnected(_ connected: Bool) {
        lock.lock()
        _isConnected = connected
        lock.unlock()
    }
    
    public func send(_ event: PhoneInputEvent) async throws {
        recordEvent(event)
        AppLogger.debug("Simulated input event received: \(event)", category: .input)
    }
    
    private func recordEvent(_ event: PhoneInputEvent) {
        lock.lock()
        lastEvent = event
        sentEventsCount += 1
        lock.unlock()
    }
}
