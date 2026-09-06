import Foundation

// Generation counter for AirPlay service enable/disable.
// Prevents a stale async start from clearing a newer listener after rapid toggles.

final class AirPlayServiceController: @unchecked Sendable {
    private let lock = NSLock()
    private var isListening = false
    private var serviceGeneration: UInt64 = 0

    /// Invalidates prior async starts and returns the new generation under lock.
    func bumpGeneration() -> UInt64 {
        lock.lock()
        serviceGeneration += 1
        let generation = serviceGeneration
        lock.unlock()
        return generation
    }

    /// Locked check that generation still matches the latest bump.
    func isCurrentGeneration(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == serviceGeneration
    }

    /// Records that NetworkStreamReceiver advertising is active.
    func markListeningStarted() {
        lock.lock()
        isListening = true
        lock.unlock()
    }

    /// Records that advertising stopped (user toggle or aborted start).
    func markListeningStopped() {
        lock.lock()
        isListening = false
        lock.unlock()
    }

    /// Locked flag used to skip redundant startListening work.
    func isAlreadyListening() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isListening
    }
}
