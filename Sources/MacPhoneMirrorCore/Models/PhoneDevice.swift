import Foundation
import CoreGraphics

public enum DeviceConnectionType: String, Codable, Sendable, CaseIterable {
    case usb = "USB (High Speed)"
    case wifi = "Wi-Fi (AirPlay)"
    case bluetooth = "Bluetooth LE"
    case simulated = "Simulator / Test"
    
    public var iconName: String {
        switch self {
        case .usb:
            return "cable.connector"
        case .wifi:
            return "wifi"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .simulated:
            return "macmini"
        }
    }
}

public struct PhoneDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var model: PhoneModel
    public var connectionType: DeviceConnectionType
    public var isAvailable: Bool
    public var isPairedForControl: Bool
    public var batteryLevel: Double? // 0.0 to 1.0
    public var osVersion: String?
    public var ipAddress: String?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        model: PhoneModel = .iPhone16Pro,
        connectionType: DeviceConnectionType = .usb,
        isAvailable: Bool = true,
        isPairedForControl: Bool = false,
        batteryLevel: Double? = nil,
        osVersion: String? = nil,
        ipAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.connectionType = connectionType
        self.isAvailable = isAvailable
        self.isPairedForControl = isPairedForControl
        self.batteryLevel = batteryLevel
        self.osVersion = osVersion
        self.ipAddress = ipAddress
    }
    
    public var screenSize: CGSize {
        model.pointSize
    }
    
    public var aspectRatio: CGFloat {
        model.aspectRatio
    }

    public var supportsScreenMirroring: Bool {
        switch connectionType {
        case .usb, .wifi:
            return true
        case .bluetooth, .simulated:
            return false
        }
    }

    public var supportsWirelessDiscovery: Bool {
        switch connectionType {
        case .wifi, .bluetooth:
            return true
        case .usb, .simulated:
            return false
        }
    }

    public var canConnect: Bool {
        supportsScreenMirroring || supportsWirelessDiscovery
    }

    public static let mockDevice = PhoneDevice(
        id: "demo-iphone-16-pro",
        name: "Someone's iPhone",
        model: .iPhone16Pro,
        connectionType: .usb,
        isAvailable: true,
        isPairedForControl: true,
        batteryLevel: 0.92,
        osVersion: "iOS 18.2"
    )
}
