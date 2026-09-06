import Foundation

// Coarse UI/session state machine (disconnected → discovering → connecting → mirroring / failed).

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case discovering
    case connecting(PhoneDevice)
    case mirroring(PhoneDevice)
    case failed(String)

    public var isConnectedOrMirroring: Bool {
        if case .mirroring = self {
            return true
        }
        return false
    }

    public var activeDevice: PhoneDevice? {
        switch self {
        case let .connecting(device), let .mirroring(device):
            device
        case .disconnected, .discovering, .failed:
            nil
        }
    }

    /// Equates by case; associated devices compare by id, failures by message.
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            true
        case (.discovering, .discovering):
            true
        case let (.connecting(lhsDevice), .connecting(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.mirroring(lhsDevice), .mirroring(rhsDevice)):
            lhsDevice.id == rhsDevice.id
        case let (.failed(lhsMessage), .failed(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}
