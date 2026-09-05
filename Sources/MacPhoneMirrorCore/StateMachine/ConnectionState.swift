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
        case let (.connecting(lhsDevice), .connecting(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.connected(lhsDevice), .connected(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.mirroring(lhsDevice), .mirroring(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.controlling(lhsDevice), .controlling(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.reconnecting(lhsDevice, lhsAttempt), .reconnecting(rhsDevice, rhsAttempt)):
            lhsDevice.id == rhsDevice.id && lhsAttempt == rhsAttempt
        case let (.failed(lhsMessage), .failed(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}
