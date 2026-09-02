import Darwin
import Foundation
import Network

final class AirPlayMirrorServer: @unchecked Sendable {
    static let shared = AirPlayMirrorServer()

    var onStreamStarted: (() -> Void)?

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.mirror", qos: .userInteractive)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var isRunning = false
    private var listeningPort: UInt16 = 0
    private var activeSession: MirrorStreamSession?
    private let h264Decoder = AirPlayH264Decoder()

    private init() {}

    func configureVideoPipeline(delegate: VideoDecoderDelegate) {
        h264Decoder.delegate = delegate
    }

    func resetSession() {
        queue.async { [weak self] in
            self?.h264Decoder.reset()
        }
    }

    func currentPort() -> UInt16 {
        queue.sync { listeningPort }
    }

    @discardableResult
    func ensureRunning() -> UInt16 {
        queue.sync {
            startListenerIfNeeded()
            return listeningPort
        }
    }

    private func startListenerIfNeeded() {
        guard !isRunning else { return }

        let fd = Darwin.socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            AppLogger.error("Mirror socket create failed errno=\(errno)", category: .airplay)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var v6Only: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))

        guard let boundPort = bindListenSocket(fd, preferredPort: 7100) else {
            AppLogger.error("Mirror socket bind failed on all candidate ports errno=\(errno)", category: .airplay)
            close(fd)
            return
        }

        guard listen(fd, 16) == 0 else {
            AppLogger.error("Mirror socket listen failed errno=\(errno)", category: .airplay)
            close(fd)
            return
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        listenFD = fd
        listeningPort = boundPort
        isRunning = true
        AppLogger.info("AirPlay mirror server listening on port \(boundPort) (socket)", category: .airplay)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        source.resume()
        acceptSource = source
    }

    private func bindListenSocket(_ fd: Int32, preferredPort: UInt16) -> UInt16? {
        var candidates: [UInt16] = [preferredPort]
        candidates.append(contentsOf: UInt16(7101) ... UInt16(7110))
        candidates.append(0)

        for port in candidates {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = in6addr_any

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            guard bindResult == 0 else { continue }

            if port == 0 {
                var storage = sockaddr_storage()
                var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
                let nameResult = withUnsafeMutablePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getsockname(fd, $0, &length)
                    }
                }
                guard nameResult == 0, storage.ss_family == sa_family_t(AF_INET6) else { return nil }
                return withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        UInt16(bigEndian: $0.pointee.sin6_port)
                    }
                }
            }

            return port
        }

        return nil
    }

    private func acceptConnections() {
        guard listenFD >= 0 else { return }

        while true {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(listenFD, $0, &length)
                }
            }
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                AppLogger.warning("Mirror accept failed errno=\(errno)", category: .airplay)
                break
            }

            configureClientSocket(clientFD)
            let endpoint = describeAddress(storage)
            AppLogger.info("Mirror stream connection from \(endpoint)", category: .airplay)

            guard let audioKey = AirPlaySessionContext.shared.currentMirrorAESKey(),
                  let streamConnectionID = AirPlaySessionContext.shared.currentMirrorStreamConnectionID()
            else {
                AppLogger.error("Mirror stream rejected: session keys unavailable", category: .airplay)
                close(clientFD)
                continue
            }

            activeSession?.stop()
            let session = MirrorStreamSession(
                socketFD: clientFD,
                audioKey: audioKey,
                streamConnectionID: streamConnectionID,
                decoder: h264Decoder,
                onStreamStarted: { [weak self] in
                    self?.onStreamStarted?()
                }
            )
            activeSession = session
            session.start(on: queue)
        }
    }

    private func configureClientSocket(_ fd: Int32) {
        var nodelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
        var keepalive: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 5000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func describeAddress(_ storage: sockaddr_storage) -> String {
        var addr = storage
        if addr.ss_family == sa_family_t(AF_INET6) {
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                    var address = ptr.pointee.sin6_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN))
                    let host = String(cString: buffer)
                    return "\(host)%\(ptr.pointee.sin6_scope_id)"
                }
            }
        }
        if addr.ss_family == sa_family_t(AF_INET) {
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                    var address = ptr.pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN))
                    return String(cString: buffer)
                }
            }
        }
        return "unknown"
    }
}

private final class MirrorStreamSession: @unchecked Sendable {
    private enum Mode {
        case handshake
        case skipPlistBody(totalLength: Int)
        case binary
    }

    private let socketFD: Int32
    private let decryptor = AirPlayMirrorDecryptor()
    private let decoder: AirPlayH264Decoder
    private let onStreamStarted: () -> Void

    private var buffer = Data()
    private var mode: Mode = .handshake
    private var pendingParameterSets = false
    private var didNotifyStreamStart = false
    private var didLogInvalidPayload = false
    private var packetCount = 0
    private var shouldStop = false
    private var didLogWaiting = false
    private var hasReceivedData = false

    init(
        socketFD: Int32,
        audioKey: Data,
        streamConnectionID: UInt64,
        decoder: AirPlayH264Decoder,
        onStreamStarted: @escaping () -> Void
    ) {
        self.socketFD = socketFD
        self.decoder = decoder
        self.onStreamStarted = onStreamStarted
        decryptor.configure(streamConnectionID: streamConnectionID, audioAESKey: audioKey)
    }

    func start(on queue: DispatchQueue) {
        queue.async { [weak self] in
            self?.readLoop()
        }
    }

    func stop() {
        shouldStop = true
        shutdown(socketFD, SHUT_RDWR)
    }

    private func readLoop() {
        defer {
            close(socketFD)
            AppLogger.info("Mirror stream session ended (\(packetCount) packets)", category: .airplay)
        }

        var idleTimeouts = 0

        while !shouldStop {
            var chunk = [UInt8](repeating: 0, count: 65536)
            let received = recv(socketFD, &chunk, chunk.count, 0)

            if received > 0 {
                hasReceivedData = true
                idleTimeouts = 0
                if buffer.isEmpty, packetCount == 0 {
                    let preview = chunk.prefix(min(received, 24)).map { String(format: "%02x", $0) }.joined(separator: " ")
                    AppLogger.info("Mirror stream first bytes (\(received)B): \(preview)", category: .airplay)
                }
                buffer.append(contentsOf: chunk.prefix(received))
                processBuffer()
                continue
            }

            if received == 0 {
                AppLogger.info("Mirror stream closed by client (\(packetCount) packets processed)", category: .airplay)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                if !hasReceivedData {
                    idleTimeouts += 1
                    if !didLogWaiting {
                        didLogWaiting = true
                        AppLogger.info("Mirror stream connected, waiting for video data...", category: .airplay)
                    }
                    if idleTimeouts > 6000 {
                        AppLogger.warning("Mirror stream timeout waiting for data (30s)", category: .airplay)
                        return
                    }
                }
                continue
            }

            AppLogger.warning("Mirror stream recv failed errno=\(errno)", category: .airplay)
            return
        }
    }

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
                        respondStreamOK()
                        buffer.removeSubrange(..<headerEnd.upperBound)
                        AppLogger.info("Mirror stream POST /stream received, plist body length=\(contentLength)", category: .airplay)
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
                AppLogger.warning("HEVC mirror stream not supported yet (\(payload.count) bytes)", category: .airplay)
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

    private func notifyStreamStartedIfNeeded() {
        guard !didNotifyStreamStart else { return }
        didNotifyStreamStart = true
        onStreamStarted()
    }

    private func looksLikeHTTPRequest(_ buffer: Data) -> Bool {
        guard let prefix = String(data: buffer.prefix(4), encoding: .utf8) else { return false }
        return prefix.hasPrefix("GET") || prefix.hasPrefix("POST")
    }

    private func looksLikeMirrorBinaryHeader(_ buffer: Data) -> Bool {
        let payloadSize = readUInt32LE(buffer, offset: 0)
        guard payloadSize >= 0, payloadSize <= 8_388_608 else { return false }
        let packetType = Int(buffer[buffer.startIndex + 4])
        return packetType <= 0x05
    }

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

    private func readUInt32LE(_ data: Data, offset: Int) -> Int {
        guard offset + 4 <= data.count else { return -1 }
        let bytes = [UInt8](data[offset ..< (offset + 4)])
        return Int(bytes[0])
            | (Int(bytes[1]) << 8)
            | (Int(bytes[2]) << 16)
            | (Int(bytes[3]) << 24)
    }

    private func respondStreamXML() {
        let config = StreamConfiguration.shared
        let size = config.quality.advertisedSize
        let height = Int(size.height)
        let width = Int(size.width)
        let refreshInterval = 1.0 / Double(config.quality.maxFPS)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>height</key><integer>\(height)</integer>
          <key>width</key><integer>\(width)</integer>
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

    private func respondStreamOK() {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        send(Data(response.utf8))
    }

    private func send(_ data: Data) {
        data.withUnsafeBytes { buffer in
            _ = Darwin.send(socketFD, buffer.baseAddress, data.count, 0)
        }
    }
}
