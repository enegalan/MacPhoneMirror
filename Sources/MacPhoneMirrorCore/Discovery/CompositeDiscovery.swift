import Combine
import Foundation

public final class CompositeDiscovery: ObservableObject, DeviceDiscovery, @unchecked Sendable {
    public static let shared = CompositeDiscovery()

    @Published public var devices: [PhoneDevice] = []

    private let usbDiscovery = USBDeviceDiscovery()
    private let bonjourDiscovery = BonjourDiscovery()
    private let bluetoothDiscovery = BluetoothDiscovery()

    private let devicesSubject = CurrentValueSubject<[PhoneDevice], Never>([])
    private var cancellables = Set<AnyCancellable>()
    private let lock = NSLock()
    private var _isScanning: Bool = false

    public var devicesPublisher: AnyPublisher<[PhoneDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    public var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    public init() {
        Publishers.CombineLatest3(
            usbDiscovery.devicesPublisher,
            bonjourDiscovery.devicesPublisher,
            bluetoothDiscovery.devicesPublisher
        )
        .map { usb, bonjour, bt -> [PhoneDevice] in
            DeviceDiscoveryFilter.mergeDiscoveredDevices(usb: usb, bonjour: bonjour, bluetooth: bt)
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] allDevices in
            self?.devicesSubject.send(allDevices)
            self?.devices = allDevices
        }
        .store(in: &cancellables)
    }

    public func start() {
        lock.lock()
        _isScanning = true
        lock.unlock()

        usbDiscovery.start()
        bonjourDiscovery.start()
        bluetoothDiscovery.start()

        AppLogger.info("Composite Device Discovery active", category: .device)
    }

    public func stop() {
        lock.lock()
        _isScanning = false
        lock.unlock()

        usbDiscovery.stop()
        bonjourDiscovery.stop()
        bluetoothDiscovery.stop()
    }

    public func refresh() {
        usbDiscovery.refreshDevices()
    }
}
