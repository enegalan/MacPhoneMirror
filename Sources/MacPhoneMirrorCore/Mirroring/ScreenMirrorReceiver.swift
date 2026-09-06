import Combine
import CoreVideo
import Foundation

// Common receiver protocol (start/stop + framePublisher) for AirPlay and USB.
// SessionManager/UI stay transport-agnostic behind this interface.

public enum ReceiverState: Sendable, Equatable {
    case idle
    case starting
    case running
    case paused
    case stopped
    case failed(String)
}

public protocol ScreenMirrorReceiver: AnyObject, Sendable {
    var state: ReceiverState { get }
    var framePublisher: AnyPublisher<VideoFrame, Never> { get }

    /// Begins capturing or advertising; throws when the transport cannot start.
    func start() async throws
    /// Stops capture/advertising and releases transport resources.
    func stop()
}
