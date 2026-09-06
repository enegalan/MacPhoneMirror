import Foundation

// Default/preferred AirPlay and HID timing constants in one place.
// Avoids magic numbers scattered across servers and SessionManager.

enum AirPlayPorts {
    static let controlDefault: UInt16 = 7000
    static let mirrorPreferred: UInt16 = 7100
    static let mirrorRange: ClosedRange<UInt16> = 7101 ... 7110
    static let timingDefault: UInt16 = 7102
}

enum AirPlayTiming {
    /// Delay after stop before re-advertising so Bonjour drops the old record.
    static let postStopRediscoverNs: UInt64 = 600_000_000
    /// Max bytes accepted per `NWConnection.receive`.
    static let receiveMaxLength = 131_072
    /// Wall-clock idle before closing an inactive mirror TCP stream.
    static let mirrorStreamIdleSeconds: TimeInterval = 30
}

enum HIDTiming {
    /// Upper bound for CBPeripheralManager power-on + GATT install + advertising.
    static let connectWaitNs: UInt64 = 15_000_000_000
    /// Short delay between HID report bursts (gestures) so iOS does not coalesce badly.
    static let shortGapNs: UInt64 = 50_000_000
}
