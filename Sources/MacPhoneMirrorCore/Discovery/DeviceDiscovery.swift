import Foundation
import Combine

public protocol DeviceDiscovery: AnyObject, Sendable {
    var devices: [PhoneDevice] { get }
    var devicesPublisher: AnyPublisher<[PhoneDevice], Never> { get }
    var isScanning: Bool { get }
    
    func start()
    func stop()
}
