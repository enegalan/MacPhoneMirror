import Foundation

final class AirPlaySessionContext: @unchecked Sendable {
    static let shared = AirPlaySessionContext()

    private let lock = NSLock()
    private(set) var isActive = false
    private(set) var controlPort: UInt16 = 7000
    private(set) var mirrorAESKey = Data()
    private(set) var mirrorStreamConnectionID: UInt64 = 0

    let sessionID = "1"

    private init() {}

    func activate(controlPort: UInt16) {
        lock.lock()
        isActive = true
        self.controlPort = controlPort
        lock.unlock()
    }

    func configureMirrorStream(aesKey: Data, streamConnectionID: UInt64) {
        lock.lock()
        mirrorAESKey = aesKey
        mirrorStreamConnectionID = streamConnectionID
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        isActive = false
        mirrorAESKey = Data()
        mirrorStreamConnectionID = 0
        lock.unlock()
    }

    func isSessionActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive
    }

    func currentControlPort() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return controlPort
    }

    func currentMirrorAESKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return mirrorAESKey.isEmpty ? nil : mirrorAESKey
    }

    func currentMirrorStreamConnectionID() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return mirrorStreamConnectionID == 0 ? nil : mirrorStreamConnectionID
    }
}
