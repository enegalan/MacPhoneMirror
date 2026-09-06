import Darwin
import Foundation

// Reads one accepted mirror TCP socket: handshake plist, then encrypted NALU stream.
// Decrypts with AirPlayMirrorDecryptor and feeds AirPlayH264Decoder.

final class MirrorStreamSession: @unchecked Sendable {
    private enum Mode {
        case handshake
        case skipPlistBody(totalLength: Int)
        case binary
    }

    private static let maxHandshakeHeaderBytes = 16384
    private static let maxPlistBodyBytes = 1_048_576

    private let socketFD: Int32
    private let decryptor = AirPlayMirrorDecryptor()
    private let decoder: AirPlayH264Decoder
    private let onStreamStarted: () -> Void
    private let onEnded: (MirrorStreamSession) -> Void
    private let stopLock = NSLock()

    private var buffer = Data()
    private var mode: Mode = .handshake
    private var pendingParameterSets = false
    private var didNotifyStreamStart = false
    private var didLogInvalidPayload = false
    private var packetCount = 0
    private var _shouldStop = false
    private var didLogWaiting = false
    private var hasReceivedData = false
    private var lastReceiveDate = Date()

    /// Opens a mirror TCP session with SETUP-derived stream keys for decrypt.
    init(
        socketFD: Int32,
        audioKey: Data,
        streamConnectionID: UInt64,
        decoder: AirPlayH264Decoder,
        onStreamStarted: @escaping () -> Void,
        onEnded: @escaping (MirrorStreamSession) -> Void
    ) {
        self.socketFD = socketFD
        self.decoder = decoder
        self.onStreamStarted = onStreamStarted
        self.onEnded = onEnded
        decryptor.configure(streamConnectionID: streamConnectionID, audioAESKey: audioKey)
    }

    /// Starts the blocking read loop on `queue`.
    func start(on queue: DispatchQueue) {
        queue.async { [weak self] in
            self?.readLoop()
        }
    }

    /// Requests shutdown and SHUT_RDWR on the client socket.
    func stop() {
        stopLock.lock()
        _shouldStop = true
        stopLock.unlock()
        shutdown(socketFD, SHUT_RDWR)
    }

    private var shouldStop: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return _shouldStop
    }

    /// Reads handshake then encrypted NALU packets until idle timeout, EOF, or error.
    private func readLoop() {
        defer {
            close(socketFD)
            AppLogger.info("Mirror stream session ended (\(packetCount) packets)", category: .airplay)
            onEnded(self)
        }

        let idleInterval = AirPlayTiming.mirrorStreamIdleSeconds
        lastReceiveDate = Date()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while !shouldStop {
            let received = recv(socketFD, &chunk, chunk.count, 0)

            if received > 0 {
                hasReceivedData = true
                lastReceiveDate = Date()
                if buffer.isEmpty, packetCount == 0 {
                    let preview = chunk.prefix(min(received, 24))
                        .map { String(format: "%02x", $0) }
                        .joined(separator: " ")
                    AppLogger.info("Mirror stream first bytes (\(received)B): \(preview)", category: .airplay)
                }
                if !appendIncoming(chunk.prefix(received)) {
                    return
                }
                processBuffer()
                continue
            }

            if received == 0 {
                AppLogger.info("Mirror stream closed by client (\(packetCount) packets processed)", category: .airplay)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                if !hasReceivedData, !didLogWaiting {
                    didLogWaiting = true
                    AppLogger.info("Mirror stream connected, waiting for video data...", category: .airplay)
                }
                if Date().timeIntervalSince(lastReceiveDate) > idleInterval {
                    AppLogger.warning("Mirror stream idle timeout (\(Int(idleInterval))s)", category: .airplay)
                    return
                }
                continue
            }

            AppLogger.warning("Mirror stream recv failed errno=\(errno)", category: .airplay)
            return
        }
    }

    /// Appends bytes with handshake/plist size limits; returns false when the session must end.
    private func appendIncoming(_ chunk: ArraySlice<UInt8>) -> Bool {
        switch mode {
        case .handshake:
            if buffer.count + chunk.count > Self.maxHandshakeHeaderBytes,
               buffer.range(of: Data("\r\n\r\n".utf8)) == nil
            {
                AppLogger.warning("Mirror stream handshake header exceeded limit", category: .airplay)
                return false
            }
        case let .skipPlistBody(totalLength):
            if totalLength > Self.maxPlistBodyBytes {
                AppLogger.warning("Mirror stream plist body exceeded limit", category: .airplay)
                return false
            }
        case .binary:
            break
        }
        buffer.append(contentsOf: chunk)
        return true
    }

    /// Advances handshake/plist-skip/binary modes as bytes arrive.
    // swiftlint:disable:next cyclomatic_complexity
    private func processBuffer() {
        while true {
            switch mode {
            case let .skipPlistBody(totalLength):
                guard buffer.count >= totalLength else { return }
                buffer.removeSubrange(..<totalLength)
                AppLogger.info("Mirror stream plist body skipped (\(totalLength) bytes)", category: .airplay)
                notifyStreamStartedIfNeeded()
                mode = .binary

            case .handshake:
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    guard let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
                        return
                    }
                    let headers = parseHTTPHeaders(headerText)

                    if headerText.hasPrefix("GET /stream.xml") {
                        respondStreamXML()
                        buffer.removeSubrange(..<headerEnd.upperBound)
                        continue
                    }

                    if headerText.hasPrefix("POST /stream") {
                        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
                        guard contentLength >= 0, contentLength <= Self.maxPlistBodyBytes else {
                            AppLogger.warning(
                                "Mirror stream rejected plist Content-Length=\(contentLength)",
                                category: .airplay
                            )
                            buffer.removeAll()
                            stop()
                            return
                        }
                        respondStreamOK()
                        buffer.removeSubrange(..<headerEnd.upperBound)
                        AppLogger.info(
                            "Mirror stream POST /stream received, plist body length=\(contentLength)",
                            category: .airplay
                        )
                        if contentLength > 0 {
                            mode = .skipPlistBody(totalLength: contentLength)
                            continue
                        }
                        notifyStreamStartedIfNeeded()
                        mode = .binary
                        continue
                    }

                    AppLogger.warning(
                        "Mirror stream unexpected HTTP request: \(headerText.split(separator: "\r\n").first ?? "")",
                        category: .airplay
                    )
                    buffer.removeSubrange(..<headerEnd.upperBound)
                    continue
                }

                if buffer.count > Self.maxHandshakeHeaderBytes {
                    AppLogger.warning("Mirror stream handshake buffer exceeded limit", category: .airplay)
                    stop()
                    return
                }

                if buffer.count >= 128, !looksLikeHTTPRequest(buffer), looksLikeMirrorBinaryHeader(buffer) {
                    AppLogger.info("Mirror stream entering binary mode (no HTTP preamble)", category: .airplay)
                    notifyStreamStartedIfNeeded()
                    mode = .binary
                    continue
                }

                return

            case .binary:
                guard processBinaryPacket() else { return }
            }
        }
    }

    /// Parses one 128-byte header + payload; returns false when more bytes are needed.
    private func processBinaryPacket() -> Bool {
        guard buffer.count >= 128 else { return false }

        let header = buffer.prefix(128)
        let payloadSize = readUInt32LE(header, offset: 0)
        guard payloadSize >= 0, payloadSize <= 8_388_608 else {
            if !didLogInvalidPayload {
                didLogInvalidPayload = true
                let preview = header.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
                AppLogger.warning("Mirror stream invalid payload size \(payloadSize), header=\(preview)", category: .airplay)
            }
            buffer.removeAll()
            return false
        }

        let totalSize = 128 + payloadSize
        guard buffer.count >= totalSize else { return false }

        let payload = buffer.subdata(in: 128 ..< totalSize)
        buffer.removeSubrange(..<totalSize)
        handleMirrorPacket(header: header, payload: payload)
        return true
    }

    /// Handles mirror packet types (0x00 video, 0x01 config/suspend, etc.).
    private func handleMirrorPacket(header: Data, payload: Data) {
        let packetType = header[header.startIndex + 4]
        packetCount += 1

        if packetCount <= 5 {
            AppLogger.info(
                "Mirror packet #\(packetCount) type=0x\(String(format: "%02x", packetType)) payload=\(payload.count)B",
                category: .airplay
            )
        }

        switch packetType {
        case 0x00:
            notifyStreamStartedIfNeeded()
            // Always decrypt to keep AES-CTR in sync, even while suspended.
            let decrypted = decryptor.decrypt(payload)
            decoder.decodeVideoPayload(decrypted, prependParameterSets: pendingParameterSets)
            pendingParameterSets = false
        case 0x01:
            notifyStreamStartedIfNeeded()
            let option = header[header.startIndex + 6]
            if option == 0x56 || option == 0x5E {
                AppLogger.info("Mirror video suspended (client screen off)", category: .airplay)
                decoder.noteStreamSuspended()
                break
            }

            if payload.count >= 8, payload.subdata(in: 4 ..< 8) == Data([0x68, 0x76, 0x63, 0x31]) {
                decoder.ingestHEVCConfig(payload)
            } else {
                decoder.ingestParameterSets(payload)
            }
            if option == 0x16 || option == 0x1E {
                decoder.noteStreamResumed()
            }
            pendingParameterSets = true
        case 0x02, 0x05:
            break
        default:
            if packetCount <= 5 {
                AppLogger.warning("Mirror packet unhandled type=0x\(String(format: "%02x", packetType))", category: .airplay)
            }
        }
    }

    /// Fires `onStreamStarted` once when the first usable stream activity arrives.
    private func notifyStreamStartedIfNeeded() {
        guard !didNotifyStreamStart else { return }
        didNotifyStreamStart = true
        onStreamStarted()
    }

    /// True when the buffer prefix looks like GET/POST HTTP.
    private func looksLikeHTTPRequest(_ buffer: Data) -> Bool {
        guard let prefix = String(data: buffer.prefix(4), encoding: .utf8) else { return false }
        return prefix.hasPrefix("GET") || prefix.hasPrefix("POST")
    }

    /// Heuristic: plausible payload size and packet type ≤ 0x05.
    private func looksLikeMirrorBinaryHeader(_ buffer: Data) -> Bool {
        let payloadSize = readUInt32LE(buffer, offset: 0)
        guard payloadSize >= 0, payloadSize <= 8_388_608 else { return false }
        let packetType = Int(buffer[buffer.startIndex + 4])
        return packetType <= 0x05
    }

    /// Parses HTTP headers from a request-line + header block string.
    private func parseHTTPHeaders(_ headerText: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() where line.contains(":") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1]
            }
        }
        return headers
    }

    /// Little-endian UInt32 at `offset`, or -1 if out of range.
    private func readUInt32LE(_ data: Data, offset: Int) -> Int {
        guard offset + 4 <= data.count else { return -1 }
        let bytes = [UInt8](data[offset ..< (offset + 4)])
        return Int(bytes[0])
            | (Int(bytes[1]) << 8)
            | (Int(bytes[2]) << 16)
            | (Int(bytes[3]) << 24)
    }

    /// Replies to GET `/stream.xml` with advertised display size plist XML.
    private func respondStreamXML() {
        let config = StreamConfiguration.shared
        let size = config.quality.advertisedSize
        let pixelSize = config.quality.advertisedPixelSize
        let height = Int(size.height)
        let width = Int(size.width)
        let heightPixels = Int(pixelSize.height)
        let widthPixels = Int(pixelSize.width)
        let refreshInterval = 1.0 / Double(config.quality.maxFPS)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>height</key><integer>\(height)</integer>
          <key>width</key><integer>\(width)</integer>
          <key>heightPixels</key><integer>\(heightPixels)</integer>
          <key>widthPixels</key><integer>\(widthPixels)</integer>
          <key>overscanned</key><false/>
          <key>refreshRate</key><real>\(refreshInterval)</real>
          <key>version</key><string>366.0</string>
        </dict>
        </plist>
        """
        let body = Data(xml.utf8)
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/x-apple-plist+xml\r\n"
        response += "Content-Length: \(body.count)\r\n\r\n"
        var data = Data(response.utf8)
        data.append(body)
        send(data)
    }

    /// Empty 200 OK for POST `/stream` before the binary NALU phase.
    private func respondStreamOK() {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        send(Data(response.utf8))
    }

    /// Sends raw bytes on the mirror client socket (best-effort).
    private func send(_ data: Data) {
        data.withUnsafeBytes { buffer in
            _ = Darwin.send(socketFD, buffer.baseAddress, data.count, 0)
        }
    }
}
