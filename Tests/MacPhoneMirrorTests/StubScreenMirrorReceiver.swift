@testable import MacPhoneMirrorCore
import Combine
import Foundation

/// Minimal `ScreenMirrorReceiver` for session/input unit tests (no frames drawn).
final class StubScreenMirrorReceiver: ScreenMirrorReceiver, @unchecked Sendable {
    private let frameSubject = PassthroughSubject<VideoFrame, Never>()

    var state: ReceiverState = .idle

    var framePublisher: AnyPublisher<VideoFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    /// Marks the stub running without allocating a pixel pipeline.
    func start() async throws {
        state = .running
    }

    /// Marks the stub stopped.
    func stop() {
        state = .stopped
    }
}
