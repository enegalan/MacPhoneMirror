import Foundation

// Process-wide active AirPlay session flags (control port, mirror AES material, stream ID).
// Lets SETUP/event handlers and the mirror server share state without circular refs.

final class AirPlaySessionContext: @unchecked Sendable {
    static let shared = AirPlaySessionContext()

    private let lock = NSLock()
    private(set) var isActive = false
    private(set) var controlPort: UInt16 = AirPlayPorts.controlDefault
    private(set) var mirrorAESKey = Data()
    private(set) var mirrorAESIV = Data()
    private(set) var mirrorStreamConnectionID: UInt64 = 0

    let sessionID = "1"

    /// Private singleton initializer.
    private init() {}

    /// Marks the RTSP session active and stores the control/event port.
    func activate(controlPort: UInt16) {
        lock.lock()
        isActive = true
        self.controlPort = controlPort
        lock.unlock()
    }

    /// Stores FairPlay-derived AES material and streamConnectionID for mirror decrypt.
    func configureMirrorStream(aesKey: Data, streamConnectionID: UInt64, aesIV: Data = Data()) {
        lock.lock()
        mirrorAESKey = aesKey
        if !aesIV.isEmpty {
            mirrorAESIV = aesIV
        }
        mirrorStreamConnectionID = streamConnectionID
        lock.unlock()
    }

    /// Clears session flags and mirror crypto material after TEARDOWN/stop.
    func deactivate() {
        lock.lock()
        isActive = false
        mirrorAESKey = Data()
        mirrorAESIV = Data()
        mirrorStreamConnectionID = 0
        lock.unlock()
    }

    /// Thread-safe read of whether an AirPlay RTSP session is active.
    func isSessionActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive
    }

    /// Thread-safe control/event port used for SETUP event transport replies.
    func currentControlPort() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return controlPort
    }

    /// Mirror AES key from SETUP, or nil when empty/unconfigured.
    func currentMirrorAESKey() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return mirrorAESKey.isEmpty ? nil : mirrorAESKey
    }

    /// Mirror AES IV (`eiv`) from SETUP, or nil when empty.
    func currentMirrorAESIV() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return mirrorAESIV.isEmpty ? nil : mirrorAESIV
    }

    /// streamConnectionID used for mirror stream key derivation, or nil if unset.
    func currentMirrorStreamConnectionID() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return mirrorStreamConnectionID == 0 ? nil : mirrorStreamConnectionID
    }
}
