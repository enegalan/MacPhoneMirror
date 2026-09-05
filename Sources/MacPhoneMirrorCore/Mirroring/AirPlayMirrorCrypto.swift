import CommonCrypto
import CryptoKit
import Foundation

enum AirPlayMirrorCrypto {
    static func deriveMirrorKeys(streamConnectionID: UInt64, audioAESKey: Data) -> (key: Data, iv: Data) {
        let keySeed = "AirPlayStreamKey\(streamConnectionID)"
        let ivSeed = "AirPlayStreamIV\(streamConnectionID)"
        let key = Data(SHA512.hash(data: Data(keySeed.utf8) + audioAESKey)).prefix(16)
        let iv = Data(SHA512.hash(data: Data(ivSeed.utf8) + audioAESKey)).prefix(16)
        return (key, iv)
    }
}

final class AirPlayMirrorDecryptor: @unchecked Sendable {
    private var cryptor: CCCryptorRef?
    private var blockOffset = 0
    private var nextDecryptCount = 0
    private var overflow = [UInt8](repeating: 0, count: 16)

    func configure(streamConnectionID: UInt64, audioAESKey: Data) {
        reset()
        let material = AirPlayMirrorCrypto.deriveMirrorKeys(
            streamConnectionID: streamConnectionID,
            audioAESKey: audioAESKey
        )
        var ivBytes = [UInt8](material.iv)
        let keyBytes = [UInt8](material.key)
        var created: CCCryptorRef?
        let status = CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            ivBytes,
            keyBytes,
            keyBytes.count,
            nil,
            0,
            0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &created
        )
        guard status == kCCSuccess, let created else { return }
        cryptor = created
        blockOffset = 0
        nextDecryptCount = 0
        overflow = [UInt8](repeating: 0, count: 16)
    }

    func decrypt(_ input: Data) -> Data {
        guard let cryptor, !input.isEmpty else { return input }

        var output = [UInt8](repeating: 0, count: input.count)
        let inputBytes = [UInt8](input)

        if nextDecryptCount > 0 {
            for index in 0 ..< nextDecryptCount {
                output[index] = inputBytes[index] ^ overflow[(16 - nextDecryptCount) + index]
            }
        }

        alignToNextBlock(cryptor)

        let bodyStart = nextDecryptCount
        let bodyLength = input.count - bodyStart
        let encryptedLength = (bodyLength / 16) * 16

        if encryptedLength > 0 {
            var processed: size_t = 0
            let status = CCCryptorUpdate(
                cryptor,
                Array(inputBytes[bodyStart ..< (bodyStart + encryptedLength)]),
                encryptedLength,
                &output[bodyStart],
                encryptedLength,
                &processed
            )
            guard status == kCCSuccess else { return input }
            blockOffset = (blockOffset + encryptedLength) % 16
        }

        let restLength = bodyLength % 16
        nextDecryptCount = 0

        if restLength > 0 {
            let restStart = input.count - restLength
            overflow = [UInt8](repeating: 0, count: 16)
            for index in 0 ..< restLength {
                overflow[index] = inputBytes[restStart + index]
            }

            alignToNextBlock(cryptor)
            var decryptedBlock = overflow
            var processed: size_t = 0
            _ = CCCryptorUpdate(cryptor, decryptedBlock, 16, &decryptedBlock, 16, &processed)
            overflow = decryptedBlock
            blockOffset = 0

            for index in 0 ..< restLength {
                output[restStart + index] = decryptedBlock[index]
            }
            nextDecryptCount = 16 - restLength
        }

        return Data(output)
    }

    func reset() {
        if let cryptor {
            CCCryptorRelease(cryptor)
        }
        cryptor = nil
        blockOffset = 0
        nextDecryptCount = 0
        overflow = [UInt8](repeating: 0, count: 16)
    }

    deinit {
        reset()
    }

    private func alignToNextBlock(_ cryptor: CCCryptorRef) {
        guard blockOffset != 0 else { return }
        var waste = [UInt8](repeating: 0, count: 16 - blockOffset)
        var processed: size_t = 0
        _ = CCCryptorUpdate(cryptor, waste, waste.count, &waste, waste.count, &processed)
        blockOffset = 0
    }
}
