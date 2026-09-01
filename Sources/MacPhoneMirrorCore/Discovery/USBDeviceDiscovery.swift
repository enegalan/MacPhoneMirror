import AVFoundation
import Combine
import Foundation

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

    override public init() {
        super.init()
    }

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

    public func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        var discovered: [PhoneDevice] = []
        for dev in discovery.devices where DeviceDiscoveryFilter.isUSBPhoneScreenDevice(dev) {
            let name = dev.localizedName
            let model = mapNameToModel(name)
            let phone = PhoneDevice(
                id: dev.uniqueID,
                name: name,
                model: model,
                connectionType: .usb,
                isAvailable: true,
                isPairedForControl: true
            )
            discovered.append(phone)
        }

        devicesSubject.send(discovered)
    }

    private func mapNameToModel(_ name: String) -> PhoneModel {
        for model in PhoneModel.allCases {
            if name.contains(model.rawValue) {
                return model
            }
        }
        return .iPhone16Pro
    }
}
