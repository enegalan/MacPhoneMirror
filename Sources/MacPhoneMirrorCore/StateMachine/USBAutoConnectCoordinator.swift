import Combine
import Foundation

// Watches USB screen devices and asks SessionManager to open a mirror session.
// Keeps USB discovery lifecycle out of SessionManager’s AirPlay path.

final class USBAutoConnectCoordinator: @unchecked Sendable {
    private let discovery = USBDeviceDiscovery()
    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private var didSetup = false
    private var _connectedUSBDeviceID: String?

    var connectedUSBDeviceID: String? {
        lock.lock()
        defer { lock.unlock() }
        return _connectedUSBDeviceID
    }

    var onDeviceAppeared: ((PhoneDevice) -> Void)?
    var onDeviceDisappeared: ((String) -> Void)?

    /// Starts USB discovery once; subsequent calls only restart discovery without rebinding sinks.
    func start() {
        lock.lock()
        let alreadySetup = didSetup
        if !alreadySetup {
            didSetup = true
        }
        lock.unlock()

        guard !alreadySetup else {
            discovery.start()
            return
        }
        discovery.start()
        discovery.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.handleDevicesUpdate(devices)
            }
            .store(in: &cancellables)
    }

    /// Cancels the device-publisher subscription and stops USB discovery.
    func stop() {
        lock.lock()
        cancellables.removeAll()
        didSetup = false
        _connectedUSBDeviceID = nil
        lock.unlock()
        discovery.stop()
    }

    /// Clears tracked USB id so the next appear event can open a fresh session.
    func clearConnectedDevice() {
        lock.lock()
        _connectedUSBDeviceID = nil
        lock.unlock()
    }

    /// Serializes read/compare/update of the connected USB id; callbacks run unlocked.
    private func handleDevicesUpdate(_ devices: [PhoneDevice]) {
        let appeared: PhoneDevice?
        let disappeared: String?

        lock.lock()
        if let usbDevice = devices.first {
            if _connectedUSBDeviceID != usbDevice.id {
                disappeared = _connectedUSBDeviceID
                _connectedUSBDeviceID = usbDevice.id
                appeared = usbDevice
            } else {
                appeared = nil
                disappeared = nil
            }
        } else if let previous = _connectedUSBDeviceID {
            _connectedUSBDeviceID = nil
            appeared = nil
            disappeared = previous
        } else {
            appeared = nil
            disappeared = nil
        }
        lock.unlock()

        if let disappeared {
            onDeviceDisappeared?(disappeared)
        }
        if let appeared {
            onDeviceAppeared?(appeared)
        }
    }
}
