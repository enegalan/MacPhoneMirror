import Foundation
import Combine
import CoreVideo

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
    
    func start() async throws
    func stop()
}
