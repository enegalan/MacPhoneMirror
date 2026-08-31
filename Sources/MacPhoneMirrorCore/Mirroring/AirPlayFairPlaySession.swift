import CAirPlayFairPlay
import Foundation

final class AirPlayFairPlaySession: @unchecked Sendable {
    static let shared = AirPlayFairPlaySession()

    private let lock = NSLock()
    private var handle: OpaquePointer?

    private init() {
        handle = fairplay_init()
    }

    deinit {
        if let handle {
            fairplay_destroy(handle)
        }
    }

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
