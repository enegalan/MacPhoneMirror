import Darwin
import Foundation
import Network

final class AirPlayTimingServer: @unchecked Sendable {
    static let shared = AirPlayTimingServer()

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.timing", qos: .userInteractive)
    private var socketFD: Int32 = -1
    private var timer: DispatchSourceTimer?
    private var receiveSource: DispatchSourceRead?
    private var remoteAddress = sockaddr_storage()
    private var remoteLength = socklen_t(0)
    private var isRunning = false
    private var didLogSendFailure = false
    private var didLogSendSuccess = false

    private init() {}

    func start(connection: NWConnection, clientTimingPort: UInt16, localPort: UInt16 = 7102) {
        queue.async { [weak self] in
            self?.startLocked(connection: connection, clientTimingPort: clientTimingPort, localPort: localPort)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func stopLocked() {
        timer?.cancel()
        timer = nil
        receiveSource?.cancel()
        receiveSource = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        isRunning = false
        didLogSendFailure = false
        didLogSendSuccess = false
    }

    private func startLocked(connection: NWConnection, clientTimingPort: UInt16, localPort: UInt16) {
        stopLocked()

        let interfaceName = Self.interfaceName(from: connection)
        guard prepareRemoteAddress(from: connection, port: clientTimingPort, interfaceName: interfaceName) else {
            AppLogger.error("Could not resolve client timing endpoint from \(connection.endpoint)", category: .airplay)
            return
        }

        let isIPv6 = remoteAddress.ss_family == sa_family_t(AF_INET6)
        socketFD = Darwin.socket(isIPv6 ? AF_INET6 : AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            AppLogger.error("Timing socket create failed", category: .airplay)
            return
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        if let interfaceName, let interfaceNameCString = interfaceName.cString(using: .utf8) {
            var ifIndex = if_nametoindex(interfaceNameCString)
            if ifIndex != 0 {
                if isIPv6 {
                    setsockopt(socketFD, IPPROTO_IPV6, IPV6_BOUND_IF, &ifIndex, socklen_t(MemoryLayout.size(ofValue: ifIndex)))
                } else {
                    setsockopt(socketFD, IPPROTO_IP, IP_BOUND_IF, &ifIndex, socklen_t(MemoryLayout.size(ofValue: ifIndex)))
                }
            }
        }

        if isIPv6 {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = localPort.bigEndian
            addr.sin6_addr = in6addr_any
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            guard bindResult == 0 else {
                AppLogger.error("Timing socket bind failed on port \(localPort) errno=\(errno)", category: .airplay)
                stopLocked()
                return
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = localPort.bigEndian
            addr.sin_addr = in_addr(s_addr: INADDR_ANY)
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                AppLogger.error("Timing socket bind failed on port \(localPort) errno=\(errno)", category: .airplay)
                stopLocked()
                return
            }
        }

        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainResponses()
        }
        source.resume()
        receiveSource = source

        isRunning = true
        AppLogger.info(
            "Timing server ready on UDP \(localPort) -> \(Self.describeAddress(remoteAddress)) port \(clientTimingPort)",
            category: .airplay
        )

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.sendTimingPacket()
        }
        timer.resume()
        self.timer = timer
    }

    private static func interfaceName(from connection: NWConnection) -> String? {
        let description = "\(connection.endpoint)"
        if let percent = description.firstIndex(of: "%") {
            let after = description[description.index(after: percent)...]
            if let dot = after.firstIndex(of: ".") {
                return String(after[..<dot])
            }
            return String(after)
        }

        if let path = connection.currentPath {
            if let iface = path.availableInterfaces.first(where: { $0.type == .wifi || $0.type == .wiredEthernet }) {
                return iface.name
            }
            return path.availableInterfaces.first?.name
        }
        return nil
    }

    private static func hostString(from connection: NWConnection, interfaceName: String?) -> String? {
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case let .hostPort(host, _) = endpoint else { return nil }

        switch host {
        case let .ipv6(ipv6):
            var hostText = "\(ipv6)"
            if hostText.hasPrefix("fe80"), let interfaceName, !hostText.contains("%") {
                hostText += "%\(interfaceName)"
            }
            return hostText
        case let .ipv4(ipv4):
            return "\(ipv4)"
        default:
            return nil
        }
    }

    private func prepareRemoteAddress(from connection: NWConnection, port: UInt16, interfaceName: String?) -> Bool {
        guard let hostText = Self.hostString(from: connection, interfaceName: interfaceName) else {
            return false
        }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = AI_NUMERICHOST

        var result: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let status = getaddrinfo(hostText, portString, &hints, &result)
        guard status == 0, let info = result else {
            AppLogger.error("getaddrinfo failed for timing host \(hostText) errno=\(status)", category: .airplay)
            return false
        }
        defer { freeaddrinfo(result) }

        guard info.pointee.ai_addrlen <= MemoryLayout<sockaddr_storage>.size else {
            return false
        }

        remoteLength = info.pointee.ai_addrlen
        withUnsafeMutablePointer(to: &remoteAddress) { storage in
            memcpy(storage, info.pointee.ai_addr, Int(remoteLength))
        }

        if remoteAddress.ss_family == sa_family_t(AF_INET6) {
            let scoped = withUnsafePointer(to: remoteAddress) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                    ptr.pointee.sin6_scope_id != 0
                }
            }
            if hostText.hasPrefix("fe80"), !scoped {
                AppLogger.warning("Link-local timing host missing scope id: \(hostText)", category: .airplay)
                return false
            }
        }

        return true
    }

    private static func describeAddress(_ storage: sockaddr_storage) -> String {
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

    private func sendTimingPacket() {
        guard isRunning, socketFD >= 0 else { return }

        var request: [UInt8] = [
            0x80, 0xD2, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]

        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let seconds = now / 1_000_000_000 + 0x83AA_7E80
        let fraction = (now % 1_000_000_000) << 32 / 1_000_000_000
        let timestamp = (seconds << 32) | fraction
        for index in 0 ..< 8 {
            request[24 + index] = UInt8((timestamp >> (56 - index * 8)) & 0xFF)
        }

        let sent = request.withUnsafeBytes { buffer in
            withUnsafePointer(to: &remoteAddress) { storage in
                storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                    sendto(socketFD, buffer.baseAddress, buffer.count, 0, pointer, remoteLength)
                }
            }
        }

        if sent < 0 {
            if !didLogSendFailure {
                didLogSendFailure = true
                AppLogger.warning(
                    "Timing packet send failed errno=\(errno) dest=\(Self.describeAddress(remoteAddress))",
                    category: .airplay
                )
            }
        } else if !didLogSendSuccess {
            didLogSendSuccess = true
            AppLogger.info("Timing packet send OK (\(sent) bytes)", category: .airplay)
        }
    }

    private func drainResponses() {
        guard socketFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 128)
        while true {
            let received = recv(socketFD, &buffer, buffer.count, 0)
            if received <= 0 {
                break
            }
            if received >= 32, !didLogSendSuccess {
                didLogSendSuccess = true
                AppLogger.info("Timing response received (\(received) bytes)", category: .airplay)
            }
        }
    }
}
