import Darwin
import Foundation

/// Accepts AirPlay realtime/buffered audio RTP/RTCP UDP so SETUP succeeds
/// and media playback does not tear down the mirror session.
/// Packets are drained (not decoded) until a real audio pipeline exists.
final class AirPlayAudioServer: @unchecked Sendable {
    static let shared = AirPlayAudioServer()

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.audio", qos: .userInteractive)
    private var dataFD: Int32 = -1
    private var controlFD: Int32 = -1
    private var dataSource: DispatchSourceRead?
    private var controlSource: DispatchSourceRead?
    private var dataPort: UInt16 = 0
    private var controlPort: UInt16 = 0
    private var isRunning = false
    private var didLogFirstData = false

    private init() {}

    /// Starts (or restarts) UDP listeners and returns bound ports.
    func ensureRunning() -> (dataPort: UInt16, controlPort: UInt16)? {
        queue.sync {
            if isRunning, dataPort > 0, controlPort > 0 {
                return (dataPort, controlPort)
            }
            return startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

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

        dataSource = makeDrainSource(fd: dataFD, label: "data")
        controlSource = makeDrainSource(fd: controlFD, label: "control")

        isRunning = true
        AppLogger.info(
            "Audio RTP sink ready dataPort=\(dataPort) controlPort=\(controlPort)",
            category: .airplay
        )
        return (dataPort, controlPort)
    }

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

    private func makeDrainSource(fd: Int32, label: String) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drain(fd: fd, label: label)
        }
        source.resume()
        return source
    }

    private func drain(fd: Int32, label: String) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let received = recv(fd, &buffer, buffer.count, Int32(MSG_DONTWAIT))
            if received <= 0 {
                break
            }
            if label == "data", !didLogFirstData {
                didLogFirstData = true
                AppLogger.info("Audio RTP first packet (\(received) bytes)", category: .airplay)
            }
        }
    }
}
