import Darwin
import Foundation
import Network

// UDP listeners for AirPlay realtime/buffered audio RTP/RTCP.
// Ports are advertised during RTSP SETUP; playback is delegated to AirPlayAudioPlayback.

final class AirPlayAudioServer: @unchecked Sendable {
    static let shared = AirPlayAudioServer()

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.audio", qos: .userInteractive)
    private let playback = AirPlayAudioPlayback()
    private var dataFD: Int32 = -1
    private var controlFD: Int32 = -1
    private var dataSource: DispatchSourceRead?
    private var controlSource: DispatchSourceRead?
    private var dataPort: UInt16 = 0
    private var controlPort: UInt16 = 0
    private var isRunning = false
    private var didLogFirstData = false
    private var expectedPeer = sockaddr_storage()
    private var expectedPeerLength: socklen_t = 0
    private var hasExpectedPeer = false
    private var hasCryptoMaterial = false

    /// Private singleton initializer.
    private init() {}

    /// Starts (or restarts) UDP listeners and returns bound ports.
    /// Returns nil if either data or control UDP bind fails.
    func ensureRunning() -> (dataPort: UInt16, controlPort: UInt16)? {
        queue.sync {
            if isRunning, dataPort > 0, controlPort > 0 {
                return (dataPort, controlPort)
            }
            return startLocked()
        }
    }

    /// Forwards RTSP SETUP audio crypto/format into the playback pipeline and binds the RTSP peer.
    func configurePlayback(_ config: AirPlayAudioPlayback.StreamConfig, peerConnection: NWConnection) {
        queue.sync {
            hasCryptoMaterial = config.sharedKey.count >= 32
                || (config.aesKey.count == 16 && config.aesIV.count == 16)
            setExpectedPeerLocked(from: peerConnection)
            playback.configure(config)
        }
    }

    /// Stops UDP sinks and resets playback state.
    func stop() {
        queue.sync { [weak self] in
            self?.stopLocked()
            self?.playback.reset()
        }
    }

    /// Binds data/control UDP sockets and attaches read sources; nil on bind failure.
    private func startLocked() -> (dataPort: UInt16, controlPort: UInt16)? {
        stopLocked()

        guard let data = bindUDPSocket(), let control = bindUDPSocket() else {
            stopLocked()
            return nil
        }

        dataFD = data.fd
        dataPort = data.port
        controlFD = control.fd
        controlPort = control.port

        dataSource = makeReadSource(fd: dataFD, label: "data")
        controlSource = makeReadSource(fd: controlFD, label: "control")

        isRunning = true
        AppLogger.info(
            "Audio RTP sink ready dataPort=\(dataPort) controlPort=\(controlPort)",
            category: .airplay
        )
        return (dataPort, controlPort)
    }

    /// Closes UDP sockets and cancels read sources on the audio queue.
    private func stopLocked() {
        dataSource?.cancel()
        dataSource = nil
        controlSource?.cancel()
        controlSource = nil
        if dataFD >= 0 {
            close(dataFD)
            dataFD = -1
        }
        if controlFD >= 0 {
            close(controlFD)
            controlFD = -1
        }
        dataPort = 0
        controlPort = 0
        isRunning = false
        didLogFirstData = false
        hasExpectedPeer = false
        expectedPeerLength = 0
        expectedPeer = sockaddr_storage()
        hasCryptoMaterial = false
    }

    /// Remembers the RTSP TCP peer so UDP datagrams from other hosts are dropped.
    private func setExpectedPeerLocked(from connection: NWConnection) {
        hasExpectedPeer = false
        expectedPeerLength = 0
        expectedPeer = sockaddr_storage()

        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case let .hostPort(host, _) = endpoint else { return }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = AI_NUMERICHOST

        let hostText: String
        switch host {
        case let .ipv4(address):
            hostText = "\(address)"
        case let .ipv6(address):
            hostText = "\(address)"
        default:
            return
        }

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostText, "0", &hints, &result)
        guard status == 0, let info = result else { return }
        defer { freeaddrinfo(result) }
        guard info.pointee.ai_addrlen <= MemoryLayout<sockaddr_storage>.size else { return }

        expectedPeerLength = info.pointee.ai_addrlen
        _ = withUnsafeMutablePointer(to: &expectedPeer) { storage in
            memcpy(storage, info.pointee.ai_addr, Int(expectedPeerLength))
        }
        hasExpectedPeer = true
    }

    /// True when `candidate` matches the negotiated peer address (port ignored).
    private func matchesExpectedPeer(_ candidate: sockaddr_storage, length: socklen_t) -> Bool {
        guard hasExpectedPeer else { return false }

        if expectedPeer.ss_family == sa_family_t(AF_INET),
           candidate.ss_family == sa_family_t(AF_INET),
           length >= socklen_t(MemoryLayout<sockaddr_in>.size)
        {
            return withUnsafePointer(to: expectedPeer) { expectedPtr in
                withUnsafePointer(to: candidate) { candidatePtr in
                    expectedPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { expected in
                        candidatePtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { remote in
                            expected.pointee.sin_addr.s_addr == remote.pointee.sin_addr.s_addr
                        }
                    }
                }
            }
        }

        if expectedPeer.ss_family == sa_family_t(AF_INET6),
           candidate.ss_family == sa_family_t(AF_INET6),
           length >= socklen_t(MemoryLayout<sockaddr_in6>.size)
        {
            return withUnsafePointer(to: expectedPeer) { expectedPtr in
                withUnsafePointer(to: candidate) { candidatePtr in
                    expectedPtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { expected in
                        candidatePtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { remote in
                            var expectedAddr = expected.pointee.sin6_addr
                            var remoteAddr = remote.pointee.sin6_addr
                            return memcmp(
                                &expectedAddr,
                                &remoteAddr,
                                MemoryLayout<in6_addr>.size
                            ) == 0
                        }
                    }
                }
            }
        }

        return false
    }

    /// Creates an IPv6 dual-stack UDP socket bound to an ephemeral port.
    private func bindUDPSocket() -> (fd: Int32, port: UInt16)? {
        let fd = Darwin.socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            AppLogger.error("Audio UDP socket create failed errno=\(errno)", category: .airplay)
            return nil
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var v6Only: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = 0
        addr.sin6_addr = in6addr_any
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bindResult == 0 else {
            AppLogger.error("Audio UDP bind failed errno=\(errno)", category: .airplay)
            close(fd)
            return nil
        }

        var bound = sockaddr_in6()
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            AppLogger.error("Audio UDP getsockname failed errno=\(errno)", category: .airplay)
            close(fd)
            return nil
        }

        let port = UInt16(bigEndian: bound.sin6_port)
        guard port > 0 else {
            close(fd)
            return nil
        }
        return (fd, port)
    }

    /// Wires a DispatchSourceRead that drains RTP/RTCP for `label` ("data"/"control").
    private func makeReadSource(fd: Int32, label: String) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drain(fd: fd, label: label)
        }
        source.resume()
        return source
    }

    /// Non-blocking recvfrom loop; forwards authenticated peer RTP into `AirPlayAudioPlayback`.
    private func drain(fd: Int32, label: String) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var sourceAddress = sockaddr_storage()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = withUnsafeMutablePointer(to: &sourceAddress) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    recvfrom(fd, &buffer, buffer.count, Int32(MSG_DONTWAIT), sockAddr, &sourceLength)
                }
            }
            if received <= 0 {
                break
            }
            if label == "data" {
                guard hasExpectedPeer, matchesExpectedPeer(sourceAddress, length: sourceLength) else {
                    continue
                }
                guard hasCryptoMaterial else { continue }
                let packet = Data(buffer.prefix(received))
                if !didLogFirstData {
                    didLogFirstData = true
                    let preview = packet.prefix(min(24, packet.count))
                        .map { String(format: "%02x", $0) }
                        .joined(separator: " ")
                    AppLogger.info(
                        "Audio RTP first packet (\(received) bytes) \(preview)",
                        category: .airplay
                    )
                }
                playback.ingestRTPPacket(packet)
            }
        }
    }
}
