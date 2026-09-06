import Darwin
import Foundation

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

    /// Forwards RTSP SETUP audio crypto/format into the playback pipeline.
    func configurePlayback(_ config: AirPlayAudioPlayback.StreamConfig) {
        queue.sync {
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

    /// Non-blocking recv loop; forwards data-port RTP into `AirPlayAudioPlayback`.
    private func drain(fd: Int32, label: String) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let received = recv(fd, &buffer, buffer.count, Int32(MSG_DONTWAIT))
            if received <= 0 {
                break
            }
            if label == "data" {
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
