import Foundation

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case discovering
    case connecting(PhoneDevice)
    case connected(PhoneDevice)
    case mirroring(PhoneDevice)
    case controlling(PhoneDevice)
    case reconnecting(PhoneDevice, attempt: Int)
    case failed(String)
    
    public var isConnectedOrMirroring: Bool {
        switch self {
        case .connected, .mirroring, .controlling:
            return true
        default:
            return false
        }
    }
    
    public var activeDevice: PhoneDevice? {
        switch self {
        case .connecting(let device),
             .connected(let device),
             .mirroring(let device),
             .controlling(let device),
             .reconnecting(let device, _):
            return device
        case .disconnected, .discovering, .failed:
            return nil
        }
    }
    
    public var statusDescription: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Waiting for AirPlay"
        case .connecting(let device):
            return "Connecting to \(device.name)..."
        case .connected(let device):
            return "Connected to \(device.name)"
        case .mirroring(let device):
            return "Mirroring \(device.name)"
        case .controlling(let device):
            return "Mirroring & Controlling \(device.name)"
        case .reconnecting(let device, let attempt):
            return "Reconnecting to \(device.name) (Attempt \(attempt))..."
        case .failed(let message):
            return "Error: \(message)"
        }
    }
    
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.discovering, .discovering):
            return true
        case (.connecting(let a), .connecting(let b)):
            return a.id == b.id
        case (.connected(let a), .connected(let b)):
            return a.id == b.id
        case (.mirroring(let a), .mirroring(let b)):
            return a.id == b.id
        case (.controlling(let a), .controlling(let b)):
            return a.id == b.id
        case (.reconnecting(let a, let attA), .reconnecting(let b, let attB)):
            return a.id == b.id && attA == attB
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
