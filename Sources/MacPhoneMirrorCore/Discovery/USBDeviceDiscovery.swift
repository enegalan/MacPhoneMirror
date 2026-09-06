import AVFoundation
import Combine
import Foundation

// Observes AVCaptureDevice connect/disconnect for wired iPhone screen capture.
// AirPlay is receiver-advertised; USB is the only path that discovers phones as capture devices.

public final class USBDeviceDiscovery: NSObject, DeviceDiscovery, @unchecked Sendable {
    private let devicesSubject = CurrentValueSubject<[PhoneDevice], Never>([])
    private let lock = NSLock()
    private var _isScanning: Bool = false
    private var notificationObservers: [NSObjectProtocol] = []

    public var devices: [PhoneDevice] {
        devicesSubject.value
    }

    public var devicesPublisher: AnyPublisher<[PhoneDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    public var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    /// Creates an idle discovery instance; call `start()` to begin observing devices.
    override public init() {
        super.init()
    }

    /// Registers AVCaptureDevice connect/disconnect observers and publishes the current device list.
    /// No-op if already scanning.
    public func start() {
        lock.lock()
        guard !_isScanning else {
            lock.unlock()
            return
        }
        _isScanning = true
        lock.unlock()

        AppLogger.info("Starting USB Device Discovery via AVFoundation", category: .device)

        let obs1 = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }

        let obs2 = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }

        notificationObservers = [obs1, obs2]
        refreshDevices()
    }

    /// Removes notification observers and marks scanning as stopped.
    public func stop() {
        lock.lock()
        _isScanning = false
        lock.unlock()

        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        AppLogger.info("Stopped USB Device Discovery", category: .device)
    }

    /// Re-enumerates external muxed capture devices and publishes filtered iPhone/iPad entries.
    public func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )

        var discovered: [PhoneDevice] = []
        for dev in discovery.devices where DeviceDiscoveryFilter.isUSBPhoneScreenDevice(dev) {
            let name = dev.localizedName
            let model = mapNameToModel(name)
            let phone = PhoneDevice(
                name: name,
                id: dev.uniqueID,
                model: model,
                connectionType: .usb,
                isAvailable: true,
                isPairedForControl: true
            )
            discovered.append(phone)
        }

        devicesSubject.send(discovered)
    }

    /// Best-effort `PhoneModel` from the capture device name; defaults to `.iPhone16Pro` when unknown.
    private func mapNameToModel(_ name: String) -> PhoneModel {
        for model in PhoneModel.allCases where name.contains(model.rawValue) {
            return model
        }
        return .iPhone16Pro
    }
}
