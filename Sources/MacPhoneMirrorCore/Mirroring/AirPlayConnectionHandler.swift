import CryptoKit
import Foundation
import Network

struct AirPlayHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let cSeq: Int
}

// swiftlint:disable:next type_body_length
final class AirPlayConnectionHandler: @unchecked Sendable {
    var onMirroringStarted: ((String) -> Void)?
    var onSessionEnded: (() -> Void)?

    private let connection: NWConnection
    private let identity: AirPlayIdentity
    private let queue: DispatchQueue
    private var buffer = Data()
    private var clientEd25519PublicKey: Data?
    private var clientECDHPublicKey: Data?
    private var ecdhPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var ecdhPublicKeyData: Data?
    private let rtspSessionID = "1"
    private let timingPort: UInt16 = 7102
    private var eventPort: UInt16 = 0
    private var aesKey = Data()
    private var aesIV = Data()
    private var streamConnectionID: UInt64 = 0
    private var hasStartedReceiving = false
    private var didLogFirstBytes = false
    private var isFinished = false
    private var sessionIsActive = false
    var controlPort: UInt16 = 7000
    private var idleTimer: DispatchWorkItem?

    init(connection: NWConnection, identity: AirPlayIdentity, queue: DispatchQueue) {
        self.connection = connection
        self.identity = identity
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isFinished else { return }

            switch state {
            case .ready:
                AppLogger.info("AirPlay connection ready", category: .airplay)
                if !hasStartedReceiving {
                    hasStartedReceiving = true
                    scheduleIdleLog()
                    receive()
                }
            case let .failed(error):
                AppLogger.error("AirPlay connection failed: \(error.localizedDescription)", category: .airplay)
                finish()
            case .cancelled:
                finish()
            case let .waiting(error):
                AppLogger.warning("AirPlay connection waiting: \(String(describing: error))", category: .airplay)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        isFinished = true
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let content, !content.isEmpty {
                cancelIdleLog()
                if !didLogFirstBytes {
                    didLogFirstBytes = true
                    let preview = content.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
                    AppLogger.info("AirPlay first bytes (\(content.count)B): \(preview)", category: .airplay)
                    if let text = String(data: content.prefix(120), encoding: .utf8), text.contains("RTSP") || text.contains("GET") || text.contains("POST") {
                        AppLogger.info("AirPlay first line: \(text.split(separator: "\r\n").first ?? "")", category: .airplay)
                    }
                }
                buffer.append(content)
                processBuffer()
            }

            if let error {
                AppLogger.warning("AirPlay receive ended: \(error.localizedDescription)", category: .airplay)
                finish()
                return
            }

            if isComplete {
                if buffer.isEmpty {
                    AppLogger.warning("AirPlay connection closed with no data", category: .airplay)
                } else {
                    AppLogger.warning("AirPlay connection closed with \(buffer.count) unparsed bytes", category: .airplay)
                }
                finish()
                return
            }

            receive()
        }
    }

    private func processBuffer() {
        while let request = parseNextRequest() {
            handle(request)
        }
    }

    private func parseNextRequest() -> AirPlayHTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            buffer.removeAll()
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where line.contains(":") {
            let split = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if split.count == 2 {
                headers[split[0].lowercased()] = split[1]
            }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let totalLength = bodyStart + contentLength
        guard buffer.count >= totalLength else { return nil }

        let body = Data(buffer[bodyStart ..< totalLength])
        buffer.removeSubrange(..<totalLength)

        let cSeq = Int(headers["cseq"] ?? "0") ?? 0
        let rawPath = parts[1]
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return AirPlayHTTPRequest(method: parts[0], path: path, headers: headers, body: body, cSeq: cSeq)
    }

    private func handle(_ request: AirPlayHTTPRequest) {
        if request.headers["session"] != nil || AirPlaySessionContext.shared.isSessionActive() {
            sessionIsActive = true
        }

        AppLogger.info("AirPlay request: \(request.method) \(request.path)", category: .airplay)

        switch request.method.uppercased() {
        case "GET" where request.path.hasPrefix("/info"):
            respondInfo(body: request.body, headers: request.headers, cSeq: request.cSeq)
        case "POST" where request.path == "/pair-setup":
            handlePairSetup(body: request.body, cSeq: request.cSeq)
        case "POST" where request.path == "/pair-verify":
            handlePairVerify(body: request.body, cSeq: request.cSeq)
        case "POST" where request.path == "/pair-pin-start":
            handlePairPinStart(cSeq: request.cSeq)
        case "POST" where request.path == "/pair-setup-pin":
            handlePairSetupPin(body: request.body, cSeq: request.cSeq)
        case "OPTIONS":
            respondOptions(cSeq: request.cSeq)
        case "SETUP":
            handleSetup(request: request)
        case "RECORD":
            handleRecord(cSeq: request.cSeq)
        case "ANNOUNCE":
            respondOK(cSeq: request.cSeq, body: Data())
        case "GET_PARAMETER":
            handleGetParameter(request: request)
        case "SET_PARAMETER":
            respondOK(cSeq: request.cSeq, body: Data())
        case "POST" where request.path == "/fp-setup":
            handleFPSetup(body: request.body, cSeq: request.cSeq)
        case "POST" where request.path == "/feedback" || request.path == "/command":
            respondOK(cSeq: request.cSeq, body: Data())
        case "TEARDOWN":
            respondOK(cSeq: request.cSeq, body: Data())
            finish()
        default:
            AppLogger.warning("Unhandled AirPlay request: \(request.method) \(request.path)", category: .airplay)
            respondOK(cSeq: request.cSeq, body: Data())
        }
    }

    private func handlePairSetup(body: Data, cSeq: Int) {
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

    private func handlePairVerify(body: Data, cSeq: Int) {
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
                let shared = try AirPlayCrypto.sharedSecret(serverPrivateKey: ecdhPrivate, clientPublicKeyData: clientECDH)
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
                let shared = try AirPlayCrypto.sharedSecret(serverPrivateKey: ecdhPrivate, clientPublicKeyData: clientECDH)
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

    private func handleFPSetup(body: Data, cSeq: Int) {
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

    private func handlePairPinStart(cSeq: Int) {
        let pin = Int.random(in: 0 ... 9999)
        DispatchQueue.main.async {
            AirPlayPairingState.shared.publishPIN(pin)
        }
        respondOK(cSeq: cSeq, body: Data())
    }

    private func handlePairSetupPin(body _: Data, cSeq: Int) {
        AppLogger.warning("pair-setup-pin requested but SRP pairing is not implemented yet", category: .airplay)
        respondError(cSeq: cSeq, code: 501, message: "Not Implemented")
    }

    private func respondInfo(body: Data, headers: [String: String], cSeq: Int) {
        do {
            let contentType = headers["content-type"]
            let hasPlistContentType = contentType?.contains("apple-binary-plist") == true

            if hasPlistContentType, !body.isEmpty {
                if let plist = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any],
                   let qualifier = plist["qualifier"] as? [String],
                   qualifier.first == "txtAirPlay"
                {
                    let bodyData = try identity.txtAirPlayInfoPlistData()
                    sendResponse(
                        status: "200 OK",
                        headers: [
                            "Content-Type": "application/x-apple-binary-plist",
                            "Content-Length": "\(bodyData.count)",
                        ],
                        body: bodyData,
                        cSeq: cSeq
                    )
                    return
                }
            }

            if hasPlistContentType {
                let bodyData = try identity.txtAirPlayInfoPlistData()
                sendResponse(
                    status: "200 OK",
                    headers: [
                        "Content-Type": "application/x-apple-binary-plist",
                        "Content-Length": "\(bodyData.count)",
                    ],
                    body: bodyData,
                    cSeq: cSeq
                )
                return
            }

            let bodyData = try identity.fullInfoPlistData()
            sendResponse(
                status: "200 OK",
                headers: [
                    "Content-Type": "application/x-apple-binary-plist",
                    "Content-Length": "\(bodyData.count)",
                ],
                body: bodyData,
                cSeq: cSeq
            )
        } catch {
            respondError(cSeq: cSeq, code: 500, message: "Internal Server Error")
        }
    }

    private func respondOptions(cSeq: Int) {
        sendResponse(
            status: "200 OK",
            headers: [
                "Public": "ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER, POST, GET",
            ],
            body: Data(),
            cSeq: cSeq
        )
    }

    private func handleSetup(request: AirPlayHTTPRequest) {
        let transport = request.headers["transport"] ?? ""

        if transport.contains("event") {
            let port = AirPlaySessionContext.shared.currentControlPort()
            sessionIsActive = true
            AppLogger.info("Event channel SETUP on port \(port)", category: .airplay)
            sendResponse(
                status: "200 OK",
                headers: [
                    "Session": rtspSessionID,
                    "Transport": "RTP/AVP/TCP;unicast;interleaved=0-1;mode=event;server_port=\(port);control_port=\(port)",
                ],
                body: Data(),
                cSeq: request.cSeq
            )
            return
        }

        guard !request.body.isEmpty else {
            respondError(cSeq: request.cSeq, code: 400, message: "Bad Request")
            return
        }

        do {
            let responseBody = try buildSetupResponse(from: request.body)
            AppLogger.info("SETUP OK (\(responseBody.count) bytes)", category: .airplay)
            sendResponse(
                status: "200 OK",
                headers: [
                    "Session": rtspSessionID,
                    "Content-Type": "application/x-apple-binary-plist",
                    "Content-Length": "\(responseBody.count)",
                ],
                body: responseBody,
                cSeq: request.cSeq
            )
        } catch {
            AppLogger.error("SETUP failed: \(error.localizedDescription)", category: .airplay)
            respondError(cSeq: request.cSeq, code: 500, message: "Internal Server Error")
        }
    }

    private func buildSetupResponse(from body: Data) throws -> Data {
        guard let root = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw SetupError.invalidPlist
        }

        var response: [String: Any] = [:]

        if let eKey = root["ekey"] as? Data,
           let eIV = root["eiv"] as? Data,
           eKey.count == 72,
           eIV.count == 16
        {
            guard let decryptedKey = AirPlayFairPlaySession.shared.decryptKey(eKey) else {
                throw SetupError.keyDecryptionFailed
            }
            aesKey = decryptedKey
            aesIV = eIV
            sessionIsActive = true
            AirPlaySessionContext.shared.activate(controlPort: controlPort)
            AirPlaySessionContext.shared.configureMirrorStream(aesKey: decryptedKey, streamConnectionID: 0)
            response["eventPort"] = Int(controlPort)
            response["timingPort"] = Int(timingPort)
            AppLogger.info("SETUP keys decrypted (eventPort=\(controlPort), timingPort=\(timingPort))", category: .airplay)
            AppLogger.info("SETUP request keys: \(root.keys.sorted())", category: .airplay)

            if let clientTimingPort = plistUInt64(root["timingPort"]).map({ UInt16($0) }), clientTimingPort > 0 {
                AppLogger.info("SETUP client timingPort=\(clientTimingPort)", category: .airplay)
                AirPlayTimingServer.shared.start(
                    connection: connection,
                    clientTimingPort: clientTimingPort,
                    localPort: timingPort
                )
            }
            _ = AirPlayMirrorServer.shared.ensureRunning()
        }

        if let streams = root["streams"] as? [[String: Any]] {
            var responseStreams: [[String: Any]] = []

            for stream in streams {
                guard let type = plistUInt64(stream["type"]) else { continue }

                if type == 110 {
                    if let streamID = plistUInt64(stream["streamConnectionID"]) {
                        streamConnectionID = streamID
                        AirPlaySessionContext.shared.configureMirrorStream(
                            aesKey: aesKey,
                            streamConnectionID: streamID
                        )
                    }

                    let mirrorPort = AirPlayMirrorServer.shared.ensureRunning()
                    guard mirrorPort > 0 else {
                        throw SetupError.mirrorServerUnavailable
                    }

                    sessionIsActive = true
                    responseStreams.append([
                        "dataPort": Int(mirrorPort),
                        "type": 110,
                    ])
                    AppLogger.info(
                        "Mirroring stream configured on port \(mirrorPort), streamConnectionID=\(streamConnectionID)",
                        category: .airplay
                    )
                }
            }

            if !responseStreams.isEmpty {
                response["streams"] = responseStreams
            }
        }

        guard !response.isEmpty else {
            throw SetupError.emptyResponse
        }

        return try PropertyListSerialization.data(fromPropertyList: response, format: .binary, options: 0)
    }

    private enum SetupError: LocalizedError {
        case invalidPlist
        case keyDecryptionFailed
        case emptyResponse
        case mirrorServerUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidPlist: "Invalid SETUP plist"
            case .keyDecryptionFailed: "FairPlay key decryption failed"
            case .emptyResponse: "No SETUP response fields"
            case .mirrorServerUnavailable: "Mirror video server could not start"
            }
        }
    }

    private func handleGetParameter(request: AirPlayHTTPRequest) {
        let contentType = request.headers["content-type"] ?? ""
        guard contentType.contains("text/parameters") else {
            respondError(cSeq: request.cSeq, code: 451, message: "Parameter not understood")
            return
        }

        let bodyText = String(data: request.body, encoding: .utf8) ?? ""
        if bodyText.contains("volume") {
            let volumeResponse = "volume: -30.000000\r\n"
            let body = Data(volumeResponse.utf8)
            sendResponse(
                status: "200 OK",
                headers: [
                    "Content-Type": "text/parameters",
                    "Content-Length": "\(body.count)",
                ],
                body: body,
                cSeq: request.cSeq
            )
            return
        }

        respondOK(cSeq: request.cSeq, body: Data())
    }

    private func plistUInt64(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            number.uint64Value
        case let value as UInt64:
            value
        case let value as Int:
            UInt64(value)
        default:
            nil
        }
    }

    private func handleRecord(cSeq: Int) {
        sendResponse(
            status: "200 OK",
            headers: [
                "Audio-Latency": "11025",
                "Audio-Jack-Status": "connected; type=analog",
            ],
            body: Data(),
            cSeq: cSeq
        )
        onMirroringStarted?("iPhone")
        AirPlayMirrorServer.shared.ensureRunning()
    }

    private func respondOK(cSeq: Int, body: Data) {
        sendResponse(
            status: "200 OK",
            headers: body.isEmpty ? [:] : ["Content-Length": "\(body.count)"],
            body: body,
            cSeq: cSeq
        )
    }

    private func respondError(cSeq: Int, code: Int, message: String) {
        sendResponse(status: "\(code) \(message)", headers: [:], body: Data(), cSeq: cSeq)
    }

    private func sendResponse(status: String, headers: [String: String], body: Data, cSeq: Int) {
        var response = "RTSP/1.0 \(status)\r\n"
        response += "Server: AirTunes/366.0\r\n"
        response += "CSeq: \(cSeq)\r\n"
        if sessionIsActive || AirPlaySessionContext.shared.isSessionActive() {
            response += "Session: \(rtspSessionID)\r\n"
        }
        for (key, value) in headers {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                AppLogger.error("AirPlay response send failed: \(error)", category: .airplay)
            }
        })
    }

    private func scheduleIdleLog() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isFinished, buffer.isEmpty else { return }
            AppLogger.warning("AirPlay connection idle after ready (no RTSP data yet)", category: .airplay)
        }
        idleTimer?.cancel()
        idleTimer = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func cancelIdleLog() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        cancelIdleLog()
        onSessionEnded?()
    }
}
