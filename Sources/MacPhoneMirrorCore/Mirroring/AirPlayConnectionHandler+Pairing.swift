import CryptoKit
import Foundation

// pair-setup / pair-verify handlers (Ed25519 + ECDH).
// Required before iOS will stream screen content to a third-party receiver.

extension AirPlayConnectionHandler {
    /// pair-setup: stores the client's Ed25519 public key and returns the receiver's key.
    /// Responds 400 when the body is not exactly 32 bytes.
    func handlePairSetup(body: Data, cSeq: Int) {
        guard body.count == 32 else {
            respondError(cSeq: cSeq, code: 400, message: "Bad Request")
            return
        }
        clientEd25519PublicKey = body
        sendResponse(
            status: "200 OK",
            headers: [
                "Content-Type": "application/octet-stream",
                "Content-Length": "32",
            ],
            body: identity.publicKeyData,
            cSeq: cSeq
        )
    }

    /// pair-verify: ECDH + AES-CTR signed exchange (step 1 request, step 2 confirm).
    /// Step 1 failure → 500; malformed bodies fall through to empty 200.
    // swiftlint:disable:next function_body_length
    func handlePairVerify(body: Data, cSeq: Int) {
        if body.count == 68, body.prefix(4) == Data([1, 0, 0, 0]) {
            let clientECDH = body.subdata(in: 4 ..< 36)
            let clientEd25519 = body.subdata(in: 36 ..< 68)
            clientEd25519PublicKey = clientEd25519
            clientECDHPublicKey = clientECDH

            let ecdhPrivate = Curve25519.KeyAgreement.PrivateKey()
            let ecdhPublic = ecdhPrivate.publicKey.rawRepresentation
            ecdhPrivateKey = ecdhPrivate
            ecdhPublicKeyData = ecdhPublic

            do {
                let shared = try AirPlayCrypto.sharedSecret(
                    serverPrivateKey: ecdhPrivate,
                    clientPublicKeyData: clientECDH
                )
                let (aesKey, aesIV) = AirPlayCrypto.derivePairVerifyKeyIV(sharedSecret: shared)
                let message = ecdhPublic + clientECDH
                let signature = try identity.signingPrivateKey.signature(for: message)
                let encryptedSignature = AirPlayCrypto.aesCTR128(data: signature, key: aesKey, iv: aesIV)
                let responseBody = ecdhPublic + encryptedSignature
                sendResponse(
                    status: "200 OK",
                    headers: [
                        "Content-Type": "application/octet-stream",
                        "Content-Length": "\(responseBody.count)",
                    ],
                    body: responseBody,
                    cSeq: cSeq
                )
            } catch {
                AppLogger.error("pair-verify step 1 failed: \(error)", category: .airplay)
                respondError(cSeq: cSeq, code: 500, message: "Internal Server Error")
            }
            return
        }

        if body.count == 68,
           body.prefix(4) == Data([0, 0, 0, 0]),
           let ecdhPrivate = ecdhPrivateKey,
           let clientECDH = clientECDHPublicKey,
           let clientEd25519 = clientEd25519PublicKey
        {
            let encryptedSignature = body.subdata(in: 4 ..< 68)
            do {
                let shared = try AirPlayCrypto.sharedSecret(
                    serverPrivateKey: ecdhPrivate,
                    clientPublicKeyData: clientECDH
                )
                let (aesKey, aesIV) = AirPlayCrypto.derivePairVerifyKeyIV(sharedSecret: shared)
                let decrypted = AirPlayCrypto.aesCTR128(data: encryptedSignature, key: aesKey, iv: aesIV)
                let message = clientECDH + ecdhPrivate.publicKey.rawRepresentation
                let clientPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: clientEd25519)
                let isValid = clientPublicKey.isValidSignature(decrypted, for: message)
                if !isValid {
                    AppLogger.warning("pair-verify client signature invalid", category: .airplay)
                }
            } catch {
                AppLogger.error("pair-verify step 2 failed: \(error)", category: .airplay)
            }

            sendResponse(
                status: "200 OK",
                headers: [
                    "Content-Type": "application/octet-stream",
                    "Content-Length": "0",
                ],
                body: Data(),
                cSeq: cSeq
            )
            return
        }

        respondOK(cSeq: cSeq, body: Data())
    }

    /// `/fp-setup`: FairPlay setup (16B) or handshake (164B) for encrypted mirroring.
    /// 400 on bad length; 500 if the C FairPlay step returns nil.
    func handleFPSetup(body: Data, cSeq: Int) {
        let response: Data?
        switch body.count {
        case 16:
            response = AirPlayFairPlaySession.shared.setup(request: body)
        case 164:
            response = AirPlayFairPlaySession.shared.handshake(request: body)
        default:
            AppLogger.error("Invalid fp-setup body length: \(body.count)", category: .airplay)
            respondError(cSeq: cSeq, code: 400, message: "Bad Request")
            return
        }

        guard let response else {
            AppLogger.error("fp-setup failed for body length \(body.count)", category: .airplay)
            respondError(cSeq: cSeq, code: 500, message: "Internal Server Error")
            return
        }

        AppLogger.info("fp-setup OK (\(body.count) -> \(response.count) bytes)", category: .airplay)
        sendResponse(
            status: "200 OK",
            headers: [
                "Content-Type": "application/octet-stream",
                "Content-Length": "\(response.count)",
            ],
            body: response,
            cSeq: cSeq
        )
    }

    /// pair-pin-start: publishes a random PIN for UI and ACKs the request.
    func handlePairPinStart(cSeq: Int) {
        let pin = Int.random(in: 0 ... 9999)
        DispatchQueue.main.async {
            AirPlayPairingState.shared.publishPIN(pin)
        }
        respondOK(cSeq: cSeq, body: Data())
    }

    /// pair-setup-pin: intentionally unimplemented (FairPlay mirroring path only).
    /// Always responds 501.
    func handlePairSetupPin(body _: Data, cSeq: Int) {
        // Screen Mirroring uses FairPlay; legacy PIN SRP is out of scope.
        AppLogger.warning("pair-setup-pin ignored (FairPlay mirroring path only)", category: .airplay)
        respondError(cSeq: cSeq, code: 501, message: "Not Implemented")
    }
}
