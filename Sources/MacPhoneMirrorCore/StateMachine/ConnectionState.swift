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
            true
        default:
            false
        }
    }

    public var activeDevice: PhoneDevice? {
        switch self {
        case let .connecting(device),
             let .connected(device),
             let .mirroring(device),
             let .controlling(device),
             let .reconnecting(device, _):
            device
        case .disconnected, .discovering, .failed:
            nil
        }
    }

    public var statusDescription: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .discovering:
            "Waiting for AirPlay"
        case let .connecting(device):
            "Connecting to \(device.name)..."
        case let .connected(device):
            "Connected to \(device.name)"
        case let .mirroring(device):
            "Mirroring \(device.name)"
        case let .controlling(device):
            "Mirroring & Controlling \(device.name)"
        case let .reconnecting(device, attempt):
            "Reconnecting to \(device.name) (Attempt \(attempt))..."
        case let .failed(message):
            "Error: \(message)"
        }
    }

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            true
        case (.discovering, .discovering):
            true
        case let (.connecting(a), .connecting(b)):
            a.id == b.id
        case let (.connected(a), .connected(b)):
            a.id == b.id
        case let (.mirroring(a), .mirroring(b)):
            a.id == b.id
        case let (.controlling(a), .controlling(b)):
            a.id == b.id
        case let (.reconnecting(a, attA), .reconnecting(b, attB)):
            a.id == b.id && attA == attB
        case let (.failed(a), .failed(b)):
            a == b
        default:
            false
        }
    }
}
