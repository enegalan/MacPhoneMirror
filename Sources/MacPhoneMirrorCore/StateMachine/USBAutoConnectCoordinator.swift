import Combine
import Foundation

// Watches USB screen devices and asks SessionManager to open a mirror session.
// Keeps USB discovery lifecycle out of SessionManager’s AirPlay path.

final class USBAutoConnectCoordinator: @unchecked Sendable {
    private let discovery = USBDeviceDiscovery()
    private var cancellables = Set<AnyCancellable>()
    private var didSetup = false
    private(set) var connectedUSBDeviceID: String?

    var onDeviceAppeared: ((PhoneDevice) -> Void)?
    var onDeviceDisappeared: ((String) -> Void)?

    /// Starts USB discovery once; subsequent calls only restart discovery without rebinding sinks.
    func start() {
        guard !didSetup else {
            discovery.start()
            return
        }
        didSetup = true
        discovery.start()
        discovery.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                if let usbDevice = devices.first {
                    if connectedUSBDeviceID != usbDevice.id {
                        if let previous = connectedUSBDeviceID {
                            onDeviceDisappeared?(previous)
                        }
                        connectedUSBDeviceID = usbDevice.id
                        onDeviceAppeared?(usbDevice)
                    }
                } else if let previous = connectedUSBDeviceID {
                    connectedUSBDeviceID = nil
                    onDeviceDisappeared?(previous)
                }
            }
            .store(in: &cancellables)
    }

    /// Clears tracked USB id so the next appear event can open a fresh session.
    func clearConnectedDevice() {
        connectedUSBDeviceID = nil
    }
}
