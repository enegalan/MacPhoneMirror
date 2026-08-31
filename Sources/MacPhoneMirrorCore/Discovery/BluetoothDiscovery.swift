import Foundation
import CoreBluetooth
import Combine

public final class BluetoothDiscovery: NSObject, DeviceDiscovery, CBCentralManagerDelegate, @unchecked Sendable {
    private var centralManager: CBCentralManager?
    private let devicesSubject = CurrentValueSubject<[PhoneDevice], Never>([])
    private let lock = NSLock()
    private var _isScanning: Bool = false
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
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
    
    public override init() {
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
        
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        AppLogger.info("Bluetooth discovery started", category: .bluetooth)
    }
    
    public func stop() {
        lock.lock()
        _isScanning = false
        lock.unlock()
        
        centralManager?.stopScan()
        AppLogger.info("Bluetooth discovery stopped", category: .bluetooth)
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isScanning {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        
        if name.contains("iPhone") || name.contains("iPad") || name.contains("iOS") {
            lock.lock()
            discoveredPeripherals[peripheral.identifier] = peripheral
            lock.unlock()
            
            let phone = PhoneDevice(
                id: peripheral.identifier.uuidString,
                name: name,
                model: .iPhone16Pro,
                connectionType: .bluetooth,
                isAvailable: true,
                isPairedForControl: true
            )
            
            var current = devicesSubject.value
            if !current.contains(where: { $0.id == phone.id }) {
                current.append(phone)
                devicesSubject.send(current)
            }
        }
    }
}
