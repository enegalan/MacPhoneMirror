import CommonCrypto
import CryptoKit
import Foundation

enum AirPlayCrypto {
    static func sha512(_ parts: [Data]) -> Data {
        var context = SHA512()
        for part in parts {
            context.update(data: part)
        }
        return Data(context.finalize())
    }

    static func derivePairVerifyKeyIV(sharedSecret: Data) -> (key: Data, iv: Data) {
        let keyMaterial = sha512([Data("Pair-Verify-AES-Key".utf8), sharedSecret])
        let ivMaterial = sha512([Data("Pair-Verify-AES-IV".utf8), sharedSecret])
        return (Data(keyMaterial.prefix(16)), Data(ivMaterial.prefix(16)))
    }

    static func aesCTR128(data: Data, key: Data, iv: Data) -> Data {
        guard key.count == 16, iv.count == 16, !data.isEmpty else { return data }

        var output = [UInt8](repeating: 0, count: data.count)
        var numBytesProcessed: size_t = 0
        var cryptor: CCCryptorRef?
        var ivBytes = [UInt8](iv)
        let keyBytes = [UInt8](key)
        let inputBytes = [UInt8](data)

        let createStatus = CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            ivBytes,
            keyBytes,
            keyBytes.count,
            nil, 0, 0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &cryptor
        )

        guard createStatus == kCCSuccess, let cryptor else {
            return data
        }

        defer { CCCryptorRelease(cryptor) }

        let updateStatus = CCCryptorUpdate(
            cryptor,
            inputBytes,
            inputBytes.count,
            &output,
            output.count,
            &numBytesProcessed
        )

        guard updateStatus == kCCSuccess else {
            return data
        }

        return Data(output.prefix(numBytesProcessed))
    }

    static func sharedSecret(serverPrivateKey: Curve25519.KeyAgreement.PrivateKey, clientPublicKeyData: Data) throws -> Data {
        let clientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPublicKeyData)
        let secret = try serverPrivateKey.sharedSecretFromKeyAgreement(with: clientKey)
        return secret.withUnsafeBytes { Data($0) }
    }
}
