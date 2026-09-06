import CAirPlayFairPlay
import Foundation

// Thin Swift wrapper around the C FairPlay setup used for encrypted AirPlay streams.
// iOS expects this handshake; without it encrypted mirroring cannot start.

final class AirPlayFairPlaySession: @unchecked Sendable {
    static let shared = AirPlayFairPlaySession()

    private let lock = NSLock()
    private var handle: OpaquePointer?

    /// Creates the underlying FairPlay C session handle.
    private init() {
        handle = fairplay_init()
    }

    deinit {
        if let handle {
            fairplay_destroy(handle)
        }
    }

    /// FairPlay `/fp-setup` first step (16-byte request → 142-byte reply).
    /// Returns nil if length is wrong, handle is missing, or C setup fails.
    func setup(request: Data) -> Data? {
        guard request.count == 16 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return nil }

        var response = [UInt8](repeating: 0, count: 142)
        let status = request.withUnsafeBytes { reqPtr in
            response.withUnsafeMutableBytes { resPtr in
                fairplay_setup(
                    handle,
                    reqPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    resPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                )
            }
        }
        return status == 0 ? Data(response) : nil
    }

    /// FairPlay `/fp-setup` handshake step (164-byte request → 32-byte reply).
    /// Returns nil on bad length or C handshake failure.
    func handshake(request: Data) -> Data? {
        guard request.count == 164 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return nil }

        var response = [UInt8](repeating: 0, count: 32)
        let status = request.withUnsafeBytes { reqPtr in
            response.withUnsafeMutableBytes { resPtr in
                fairplay_handshake(
                    handle,
                    reqPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    resPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                )
            }
        }
        return status == 0 ? Data(response) : nil
    }

    /// Decrypts FairPlay `ekey` from RTSP SETUP into the 16-byte stream AES key.
    /// Returns nil unless `encryptedKey` is 72 bytes and C decrypt succeeds.
    func decryptKey(_ encryptedKey: Data) -> Data? {
        guard encryptedKey.count == 72 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return nil }

        var output = [UInt8](repeating: 0, count: 16)
        let status = encryptedKey.withUnsafeBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                fairplay_decrypt(
                    handle,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                )
            }
        }
        return status == 0 ? Data(output) : nil
    }
}
