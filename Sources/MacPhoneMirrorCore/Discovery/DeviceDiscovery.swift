import Combine
import Foundation

// Protocol for reactive device scanning.
// Decouples SessionManager from USB (or future) discovery implementations.

public protocol DeviceDiscovery: AnyObject, Sendable {
    var devices: [PhoneDevice] { get }
    var devicesPublisher: AnyPublisher<[PhoneDevice], Never> { get }
    var isScanning: Bool { get }

    /// Begins scanning and publishing discovered devices.
    func start()
    /// Stops scanning and tears down observation.
    func stop()
}
