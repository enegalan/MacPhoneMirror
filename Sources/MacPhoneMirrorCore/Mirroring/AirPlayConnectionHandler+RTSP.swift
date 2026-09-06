import Foundation
import Network

// RTSP METHODS (OPTIONS, SETUP, RECORD, TEARDOWN, …) that negotiate video/audio/event channels.
// Split from the connection handler to keep the request router small.

extension AirPlayConnectionHandler {
    /// RTSP SETUP: event-channel transport or binary-plist stream negotiation.
    /// 400 when a non-event SETUP has an empty body; 500 on build failure.
    func handleSetup(request: AirPlayHTTPRequest) {
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

    /// Builds the SETUP binary-plist: FairPlay ekey decrypt, timing, type-110/audio ports.
    /// Throws when plist/keys/ports cannot be prepared for the phone.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func buildSetupResponse(from body: Data) throws -> Data {
        guard let root = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw SetupError.invalidPlist
        }

        AppLogger.info("SETUP request keys: \(root.keys.sorted())", category: .airplay)

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
            AirPlaySessionContext.shared.configureMirrorStream(
                aesKey: decryptedKey,
                streamConnectionID: 0,
                aesIV: eIV
            )
            response["eventPort"] = Int(controlPort)
            response["timingPort"] = Int(timingPort)
            AppLogger.info("SETUP keys decrypted (eventPort=\(controlPort), timingPort=\(timingPort))", category: .airplay)

            // Newer iOS clients send this flag and expect /info-like fields in SETUP 1.
            if root["combinedGetInfoWithControlSetup"] as? Bool == true
                || (root["combinedGetInfoWithControlSetup"] as? NSNumber)?.boolValue == true
            {
                if let infoData = try? identity.fullInfoPlistData(),
                   let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
                {
                    for (key, value) in info where response[key] == nil {
                        response[key] = value
                    }
                    AppLogger.info("SETUP merged /info fields for combinedGetInfoWithControlSetup", category: .airplay)
                }
            }

            if let clientTimingPort = plistUInt16(root["timingPort"]), clientTimingPort > 0 {
                AppLogger.info("SETUP client timingPort=\(clientTimingPort)", category: .airplay)
                AirPlayTimingServer.shared.start(
                    connection: connection,
                    clientTimingPort: clientTimingPort,
                    localPort: timingPort
                )
            }
            _ = AirPlayMirrorServer.shared.ensureRunning()
        }

        let streamDicts = setupStreamDictionaries(from: root)
        if !streamDicts.isEmpty {
            var responseStreams: [[String: Any]] = []
            let requestedTypes = streamDicts.compactMap { plistUInt64($0["type"]) }
            AppLogger.info("SETUP streams types=\(requestedTypes)", category: .airplay)

            for stream in streamDicts {
                guard let type = plistUInt64(stream["type"]) else { continue }

                if type == 110 {
                    let mirrorKey = aesKey.isEmpty
                        ? (AirPlaySessionContext.shared.currentMirrorAESKey() ?? Data())
                        : aesKey
                    if let streamID = plistUInt64(stream["streamConnectionID"]) {
                        streamConnectionID = streamID
                        AirPlaySessionContext.shared.configureMirrorStream(
                            aesKey: mirrorKey,
                            streamConnectionID: streamID,
                            aesIV: aesIV
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
                    onMirroringStarted?("iPhone")
                    AirPlayMirrorServer.shared.ensureRunning()
                } else if type == 96 || type == 103 {
                    // Realtime (96) or buffered (103) audio. Accept SETUP so media
                    // playback does not abort the mirror session.
                    guard let ports = AirPlayAudioServer.shared.ensureRunning() else {
                        throw SetupError.audioServerUnavailable
                    }

                    var audioConfig = AirPlayAudioPlayback.StreamConfig()
                    if let ct = plistUInt64(stream["ct"]) {
                        audioConfig.compressionType = ct
                    }
                    if let format = plistUInt64(stream["audioFormat"]) {
                        audioConfig.audioFormat = format
                    }
                    if let sr = plistUInt64(stream["sr"]) {
                        audioConfig.sampleRate = Double(sr)
                    } else if audioConfig.sampleRate <= 0 {
                        audioConfig.sampleRate = 44100
                    }
                    if let spf = plistUInt64(stream["spf"]) {
                        audioConfig.samplesPerFrame = spf
                    } else if audioConfig.compressionType == 8 {
                        audioConfig.samplesPerFrame = 480
                    }
                    if let shk = stream["shk"] as? Data {
                        audioConfig.sharedKey = shk
                    }
                    // Screen-mirroring AAC-ELD uses FairPlay AES-CBC (aeskey + eiv), not shk.
                    let sessionKey = aesKey.isEmpty
                        ? (AirPlaySessionContext.shared.currentMirrorAESKey() ?? Data())
                        : aesKey
                    let sessionIV = aesIV.isEmpty
                        ? (AirPlaySessionContext.shared.currentMirrorAESIV() ?? Data())
                        : aesIV
                    audioConfig.aesKey = sessionKey
                    audioConfig.aesIV = sessionIV
                    AirPlayAudioServer.shared.configurePlayback(audioConfig, peerConnection: connection)

                    sessionIsActive = true
                    responseStreams.append([
                        "dataPort": Int(ports.dataPort),
                        "controlPort": Int(ports.controlPort),
                        "type": Int(type),
                    ])
                    AppLogger.info(
                        "Audio stream type=\(type) ct=\(audioConfig.compressionType) "
                            + "sr=\(Int(audioConfig.sampleRate)) dataPort=\(ports.dataPort) "
                            + "controlPort=\(ports.controlPort)",
                        category: .airplay
                    )
                } else {
                    // Unknown stream (often media/audio variants). Still accept with an
                    // RTP sink so the phone does not tear down the mirror session.
                    guard let responseType = Int(exactly: type) else { continue }
                    AppLogger.warning(
                        "SETUP accepting unknown stream type=\(responseType) as audio sink",
                        category: .airplay
                    )
                    guard let ports = AirPlayAudioServer.shared.ensureRunning() else {
                        throw SetupError.audioServerUnavailable
                    }
                    sessionIsActive = true
                    responseStreams.append([
                        "dataPort": Int(ports.dataPort),
                        "controlPort": Int(ports.controlPort),
                        "type": responseType,
                    ])
                }
            }

            if !responseStreams.isEmpty {
                response["streams"] = responseStreams
            }
        } else if root["streams"] != nil {
            AppLogger.warning(
                "SETUP streams present but unreadable (type=\(String(describing: type(of: root["streams"]!))))",
                category: .airplay
            )
        }

        // Session refresh / no-op SETUP during an active mirror: keep the client alive.
        if response.isEmpty, sessionIsActive || AirPlaySessionContext.shared.isSessionActive() {
            response["eventPort"] = Int(AirPlaySessionContext.shared.currentControlPort())
            response["timingPort"] = Int(timingPort)
            AppLogger.info("SETUP session refresh (eventPort/timingPort only)", category: .airplay)
        }

        guard !response.isEmpty else {
            throw SetupError.emptyResponse
        }

        return try PropertyListSerialization.data(fromPropertyList: response, format: .binary, options: 0)
    }

    /// Plist `streams` often fails `as? [[String: Any]]` when nested values vary.
    func setupStreamDictionaries(from root: [String: Any]) -> [[String: Any]] {
        if let streams = root["streams"] as? [[String: Any]] {
            return streams
        }
        guard let items = root["streams"] as? [Any] else { return [] }
        return items.compactMap { item in
            if let stream = item as? [String: Any] {
                return stream
            }
            if let stream = item as? [AnyHashable: Any] {
                var converted: [String: Any] = [:]
                for (key, value) in stream {
                    guard let stringKey = key as? String else { continue }
                    converted[stringKey] = value
                }
                return converted.isEmpty ? nil : converted
            }
            return nil
        }
    }

    /// RTSP TEARDOWN: stops audio-only or ends the full mirror session.
    func handleTeardown(request: AirPlayHTTPRequest) {
        var teardownAudio = false
        var teardownVideo = false

        if !request.body.isEmpty,
           let root = try? PropertyListSerialization.propertyList(from: request.body, format: nil) as? [String: Any]
        {
            let streams = setupStreamDictionaries(from: root)
            for stream in streams {
                guard let type = plistUInt64(stream["type"]) else { continue }
                if type == 110 {
                    teardownVideo = true
                } else {
                    // 96/103 and other media streams: drop audio sink only.
                    teardownAudio = true
                }
            }
        }

        AppLogger.info(
            "TEARDOWN audio=\(teardownAudio) video=\(teardownVideo) body=\(request.body.count)B",
            category: .airplay
        )
        respondOK(cSeq: request.cSeq, body: Data())

        if teardownAudio, !teardownVideo {
            AirPlayAudioServer.shared.stop()
            return
        }

        AirPlayAudioServer.shared.stop()
        finish()
    }

    private enum SetupError: LocalizedError {
        case invalidPlist
        case keyDecryptionFailed
        case emptyResponse
        case mirrorServerUnavailable
        case audioServerUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidPlist: "Invalid SETUP plist"
            case .keyDecryptionFailed: "FairPlay key decryption failed"
            case .emptyResponse: "No SETUP response fields"
            case .mirrorServerUnavailable: "Mirror video server could not start"
            case .audioServerUnavailable: "Audio RTP sink could not start"
            }
        }
    }

    /// GET_PARAMETER for text/parameters (e.g. volume); 451 for other content types.
    func handleGetParameter(request: AirPlayHTTPRequest) {
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

    /// Coerces plist numeric values to UInt64 for stream type / port fields.
    func plistUInt64(_ value: Any?) -> UInt64? {
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

    /// Coerces plist numerics to UInt16 only when the value fits without truncation.
    func plistUInt16(_ value: Any?) -> UInt16? {
        guard let value = plistUInt64(value), value <= UInt64(UInt16.max) else { return nil }
        return UInt16(value)
    }

    /// RTSP RECORD: ACK with audio latency headers and ensure the mirror TCP listener is up.
    func handleRecord(cSeq: Int) {
        sendResponse(
            status: "200 OK",
            headers: [
                "Audio-Latency": "11025",
                "Audio-Jack-Status": "connected; type=analog",
            ],
            body: Data(),
            cSeq: cSeq
        )
        // Window opens on type-110 SETUP; RECORD alone is not enough for mirror video.
        AirPlayMirrorServer.shared.ensureRunning()
    }

    /// Sends a minimal RTSP 200 OK, optionally with a body Content-Length.
    func respondOK(cSeq: Int, body: Data) {
        sendResponse(
            status: "200 OK",
            headers: body.isEmpty ? [:] : ["Content-Length": "\(body.count)"],
            body: body,
            cSeq: cSeq
        )
    }

    /// Sends an RTSP error status line with an empty body.
    func respondError(cSeq: Int, code: Int, message: String) {
        sendResponse(status: "\(code) \(message)", headers: [:], body: Data(), cSeq: cSeq)
    }

    /// Serializes and sends one RTSP/1.0 response on the control connection.
    func sendResponse(status: String, headers: [String: String], body: Data, cSeq: Int) {
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
}
