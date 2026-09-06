import Darwin
import Foundation
import Network

// TCP acceptor for the encrypted mirror video stream and handoff to MirrorStreamSession.
// Separates listening/accept from per-connection binary framing and decode.

final class AirPlayMirrorServer: @unchecked Sendable {
    static let shared = AirPlayMirrorServer()

    var onStreamStarted: (() -> Void)?

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.mirror", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.macphonemirror.airplay.mirror.session", qos: .userInteractive)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var isRunning = false
    private var listeningPort: UInt16 = 0
    private var activeSession: MirrorStreamSession?
    private let h264Decoder = AirPlayH264Decoder()

    /// Private singleton initializer.
    private init() {}

    /// Attaches the H.264 decoder delegate used to publish frames to the UI.
    func configureVideoPipeline(delegate: VideoDecoderDelegate) {
        h264Decoder.delegate = delegate
    }

    /// Resets decoder state between sessions without tearing down the TCP listener.
    func resetSession() {
        sessionQueue.async { [weak self] in
            self?.h264Decoder.reset()
        }
    }

    /// Currently bound mirror TCP port, or 0 if not listening.
    func currentPort() -> UInt16 {
        queue.sync { listeningPort }
    }

    /// Ensures the mirror TCP acceptor is listening; returns the bound port (0 on failure).
    @discardableResult
    func ensureRunning() -> UInt16 {
        queue.sync {
            startListenerIfNeeded()
            return listeningPort
        }
    }

    /// Tears down the TCP accept socket and any active mirror stream.
    func shutdown() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 {
                close(listenFD)
                listenFD = -1
            }
            listeningPort = 0
            isRunning = false

            let session = activeSession
            activeSession = nil
            session?.stop()
            AppLogger.info("AirPlay mirror server shut down", category: .airplay)
        }
        sessionQueue.async { [weak self] in
            self?.h264Decoder.reset()
        }
    }

    /// Creates/binds/listens the dual-stack TCP socket and installs the accept source.
    private func startListenerIfNeeded() {
        guard !isRunning else { return }

        let fd = Darwin.socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            AppLogger.error("Mirror socket create failed errno=\(errno)", category: .airplay)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var v6Only: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))

        guard let boundPort = bindListenSocket(fd, preferredPort: AirPlayPorts.mirrorPreferred) else {
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

    /// Tries preferred/range/ephemeral ports; returns the bound port or nil.
    private func bindListenSocket(_ fd: Int32, preferredPort: UInt16) -> UInt16? {
        var candidates: [UInt16] = [preferredPort]
        candidates.append(contentsOf: AirPlayPorts.mirrorRange)
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

    /// Accepts pending clients and starts `MirrorStreamSession` when SETUP keys exist.
    /// Closes the client if AES key / streamConnectionID are unavailable.
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

            let session = MirrorStreamSession(
                socketFD: clientFD,
                audioKey: audioKey,
                streamConnectionID: streamConnectionID,
                decoder: h264Decoder,
                onStreamStarted: { [weak self] in
                    self?.onStreamStarted?()
                },
                onEnded: { [weak self] ended in
                    self?.queue.async {
                        if self?.activeSession === ended {
                            self?.activeSession = nil
                        }
                    }
                }
            )

            let previous = activeSession
            activeSession = session
            previous?.stop()
            session.start(on: sessionQueue)
        }
    }

    /// Clears O_NONBLOCK and sets TCP_NODELAY / keepalive / short RCVTIMEO.
    private func configureClientSocket(_ fd: Int32) {
        // Darwin accept() inherits O_NONBLOCK from the listen socket. Clear it so
        // SO_RCVTIMEO actually waits; otherwise the idle loop spins and FIN's the
        // peer before video arrives (release builds).
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        }

        var nodelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
        var keepalive: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 5000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Formats a sockaddr for logging (IPv6 includes scope id).
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
