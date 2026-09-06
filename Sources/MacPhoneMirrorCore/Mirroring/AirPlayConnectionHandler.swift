import CryptoKit
import Foundation
import Network

// Per-TCP-connection AirPlay/RTSP request loop (buffer, parse, dispatch).
// Owns pairing/crypto session state for one iPhone connection.

final class AirPlayConnectionHandler: @unchecked Sendable {
    var onMirroringStarted: ((String) -> Void)?
    var onSessionEnded: (() -> Void)?

    let connection: NWConnection
    let identity: AirPlayIdentity
    private let queue: DispatchQueue
    private var buffer = Data()
    var clientEd25519PublicKey: Data?
    var clientECDHPublicKey: Data?
    var ecdhPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    var ecdhPublicKeyData: Data?
    let rtspSessionID = "1"
    let timingPort: UInt16 = AirPlayPorts.timingDefault
    var eventPort: UInt16 = 0
    var aesKey = Data()
    var aesIV = Data()
    var streamConnectionID: UInt64 = 0
    private var hasStartedReceiving = false
    private var didLogFirstBytes = false
    private var isFinished = false
    var sessionIsActive = false
    var controlPort: UInt16 = AirPlayPorts.controlDefault
    private var idleTimer: DispatchWorkItem?

    /// Binds this handler to one TCP connection and shared receiver identity.
    init(connection: NWConnection, identity: AirPlayIdentity, queue: DispatchQueue) {
        self.connection = connection
        self.identity = identity
        self.queue = queue
    }

    /// Starts the NWConnection and begins the RTSP/HTTP receive loop when ready.
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

    /// Cancels the underlying connection without waiting for a graceful TEARDOWN.
    func cancel() {
        isFinished = true
        connection.cancel()
    }

    /// Issues the next `NWConnection.receive` for RTSP/HTTP bytes.
    private func receive() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: AirPlayTiming.receiveMaxLength
        ) { [weak self] content, _, isComplete, error in
            self?.handleReceive(content: content, isComplete: isComplete, error: error)
        }
    }

    /// Appends bytes, parses requests, and finishes on error or EOF.
    private func handleReceive(content: Data?, isComplete: Bool, error: Error?) {
        if let content, !content.isEmpty {
            cancelIdleLog()
            if !didLogFirstBytes {
                didLogFirstBytes = true
                let preview = content.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
                AppLogger.info("AirPlay first bytes (\(content.count)B): \(preview)", category: .airplay)
                if let text = String(data: content.prefix(120), encoding: .utf8),
                   text.contains("RTSP") || text.contains("GET") || text.contains("POST")
                {
                    AppLogger.info(
                        "AirPlay first line: \(text.split(separator: "\r\n").first ?? "")",
                        category: .airplay
                    )
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
                AppLogger.warning(
                    "AirPlay connection closed with \(buffer.count) unparsed bytes",
                    category: .airplay
                )
            }
            finish()
            return
        }

        receive()
    }

    /// Dispatches every complete request currently buffered.
    private func processBuffer() {
        while let request = parseNextRequest() {
            handle(request)
        }
    }

    /// Pulls one framed HTTP/RTSP request from `buffer`, or nil if incomplete.
    private func parseNextRequest() -> AirPlayHTTPRequest? {
        AirPlayHTTPParser.parseNextRequest(from: &buffer)
    }

    /// Routes one AirPlay/RTSP method to the pairing, SETUP, or info handlers.
    // swiftlint:disable:next cyclomatic_complexity
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
        case "POST" where request.path == "/feedback"
            || request.path == "/command"
            || request.path == "/audioMode":
            respondOK(cSeq: request.cSeq, body: Data())
        case "TEARDOWN":
            handleTeardown(request: request)
        default:
            AppLogger.warning("Unhandled AirPlay request: \(request.method) \(request.path)", category: .airplay)
            respondOK(cSeq: request.cSeq, body: Data())
        }
    }

    /// Answers GET `/info` with TXT or full receiver plist; 500 on serialize failure.
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

    /// RTSP OPTIONS: advertises supported methods to the phone.
    private func respondOptions(cSeq: Int) {
        sendResponse(
            status: "200 OK",
            headers: [
                "Public":
                    "ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER, POST, GET",
            ],
            body: Data(),
            cSeq: cSeq
        )
    }

    /// Schedules a warning if the connection stays idle after becoming ready.
    private func scheduleIdleLog() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isFinished, buffer.isEmpty else { return }
            AppLogger.warning("AirPlay connection idle after ready (no RTSP data yet)", category: .airplay)
        }
        idleTimer?.cancel()
        idleTimer = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Cancels the pending idle-connection warning timer.
    private func cancelIdleLog() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    /// Ends the session once: notifies observers and cancels the TCP connection.
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        cancelIdleLog()
        onSessionEnded?()
        connection.cancel()
    }
}
