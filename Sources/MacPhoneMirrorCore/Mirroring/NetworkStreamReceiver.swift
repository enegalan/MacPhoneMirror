import Combine
import CoreMedia
import CoreVideo
import Foundation
import Network

// Public ScreenMirrorReceiver for AirPlay: advertises Bonjour, owns control listener,
// and publishes decoded frames / orientation / session start-end to SessionManager.

public final class NetworkStreamReceiver: NSObject, ScreenMirrorReceiver, VideoDecoderDelegate, @unchecked Sendable {
    public static let shared = NetworkStreamReceiver()

    private let mirroringStartedSubject = PassthroughSubject<String, Never>()
    private let sessionEndedSubject = PassthroughSubject<Void, Never>()
    private let orientationSubject = PassthroughSubject<DeviceOrientation, Never>()

    public var mirroringStartedPublisher: AnyPublisher<String, Never> {
        mirroringStartedSubject.eraseToAnyPublisher()
    }

    public var sessionEndedPublisher: AnyPublisher<Void, Never> {
        sessionEndedSubject.eraseToAnyPublisher()
    }

    public var orientationPublisher: AnyPublisher<DeviceOrientation, Never> {
        orientationSubject.eraseToAnyPublisher()
    }

    private let frameSubject = PassthroughSubject<VideoFrame, Never>()
    private let queue = DispatchQueue(label: "com.macphonemirror.network.receiver", qos: .userInteractive)
    private let lock = NSLock()

    private var listener: NWListener?
    private var activeHandlers: [ObjectIdentifier: AirPlayConnectionHandler] = [:]
    private var _state: ReceiverState = .idle
    private var frameCounter: UInt64 = 0
    private var latestFrame: VideoFrame?
    private var lastReportedOrientation: DeviceOrientation = .portrait
    private var advertisedPort: UInt16 = 0
    private let identity = AirPlayIdentity.loadOrCreate()

    public var state: ReceiverState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var framePublisher: AnyPublisher<VideoFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public var isAdvertising: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .running = _state {
            return true
        }
        return false
    }

    /// Loads identity and wires the shared mirror server to this receiver.
    override private init() {
        super.init()
        AirPlayMirrorServer.shared.configureVideoPipeline(delegate: self)
        AirPlayMirrorServer.shared.onStreamStarted = { [weak self] in
            self?.mirroringStartedSubject.send("iPhone")
        }
    }

    /// Thread-safe update of `ReceiverState`.
    private func setState(_ newState: ReceiverState) {
        lock.lock()
        _state = newState
        lock.unlock()
    }

    /// True when advertising/running.
    private func isRunningState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .running = _state {
            return true
        }
        return false
    }

    /// True when start should no-op because already starting or running.
    private func shouldSkipStart() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch _state {
        case .running, .starting:
            return true
        default:
            return false
        }
    }

    /// Advertises `_airplay._tcp` and ensures the mirror TCP server is ready.
    public func start() async throws {
        if shouldSkipStart() {
            return
        }

        // After an explicit stop, give Bonjour time to drop the old record
        // so iPhone Screen Mirroring rediscovers a fresh advertisement.
        let wasStopped: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if case .stopped = _state {
                return true
            }
            return false
        }()
        if wasStopped {
            try await Task.sleep(nanoseconds: AirPlayTiming.postStopRediscoverNs)
        }

        do {
            try await startListener(on: .any)
            let mirrorPort = AirPlayMirrorServer.shared.ensureRunning()
            if mirrorPort == 0 {
                AppLogger.warning("Mirror server did not start at launch; will retry during SETUP", category: .airplay)
            }
        } catch {
            AppLogger.error("AirPlay listener could not start: \(error.localizedDescription)", category: .airplay)
            throw error
        }
    }

    /// Creates the Bonjour NWListener for AirPlay control on `port`.
    private func startListener(on port: NWEndpoint.Port) async throws {
        setState(.starting)

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let listener = try NWListener(using: params, on: port)
        let txtRecord = AirPlayTXTRecordBuilder.makeRecord(identity: identity)
        listener.service = NWListener.Service(
            name: AirPlayTXTRecordBuilder.serviceName,
            type: "_airplay._tcp",
            domain: "local.",
            txtRecord: txtRecord
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bindListener(listener, resumeOnce: ResumeOnce(continuation: continuation))
        }
    }

    /// Installs state/connection handlers and starts `listener` on the receiver queue.
    private func bindListener(_ listener: NWListener, resumeOnce: ResumeOnce) {
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state, listener: listener, resumeOnce: resumeOnce)
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }

        lock.lock()
        self.listener?.cancel()
        self.listener = listener
        lock.unlock()

        listener.start(queue: queue)
    }

    /// Maps NWListener state to receiver state and resumes the start continuation once.
    private func handleListenerState(
        _ state: NWListener.State,
        listener: NWListener,
        resumeOnce: ResumeOnce
    ) {
        lock.lock()
        let isCurrent = self.listener === listener
        lock.unlock()
        guard isCurrent else {
            if case .cancelled = state {
                resumeOnce.fail(CancellationError())
            }
            return
        }

        switch state {
        case .ready:
            if let actualPort = listener.port?.rawValue {
                advertisedPort = actualPort
            }
            setState(.running)
            AppLogger.info(
                "AirPlay receiver advertising '\(AirPlayTXTRecordBuilder.serviceName)' on port \(advertisedPort)",
                category: .airplay
            )
            resumeOnce.complete()
        case let .failed(error):
            setState(.failed(error.localizedDescription))
            AppLogger.error("AirPlay listener failed: \(error)", category: .airplay)
            resumeOnce.fail(error)
        case .cancelled:
            setState(.stopped)
            resumeOnce.fail(CancellationError())
        default:
            break
        }
    }

    /// Spawns an `AirPlayConnectionHandler` for one control TCP connection.
    private func handleIncomingConnection(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        AppLogger.info("Incoming AirPlay connection from \(connection.endpoint)", category: .network)

        let handler = AirPlayConnectionHandler(connection: connection, identity: identity, queue: queue)
        handler.controlPort = advertisedPort
        handler.onMirroringStarted = { [weak self] deviceName in
            self?.mirroringStartedSubject.send(deviceName)
        }
        handler.onSessionEnded = { [weak self, weak handler] in
            self?.handleConnectionEnded(
                connectionID,
                sessionWasActive: handler?.sessionIsActive == true
            )
        }

        lock.lock()
        activeHandlers[connectionID] = handler
        lock.unlock()

        handler.start()
    }

    /// Cleans up a finished handler; full session reset only when the RTSP session was active.
    private func handleConnectionEnded(_ connectionID: ObjectIdentifier, sessionWasActive: Bool) {
        lock.lock()
        let removed = activeHandlers.removeValue(forKey: connectionID) != nil
        let leftovers = Array(activeHandlers.values)
        let hasActiveHandlers = !leftovers.isEmpty
        lock.unlock()

        guard removed else { return }

        if sessionWasActive {
            lock.lock()
            activeHandlers.removeAll()
            lock.unlock()
            for handler in leftovers {
                handler.cancel()
            }
            resetSessionState()
            sessionEndedSubject.send(())
            return
        }

        // Short-lived sockets (GET /info, probes) must not tear down an active mirror.
        if hasActiveHandlers || leftovers.contains(where: \.sessionIsActive)
            || AirPlaySessionContext.shared.isSessionActive()
        {
            AppLogger.info(
                "AirPlay auxiliary connection ended (activeHandlers=\(hasActiveHandlers))",
                category: .airplay
            )
            return
        }

        resetSessionState()
        sessionEndedSubject.send(())
    }

    /// Cancels active handlers and clears session audio/timing/mirror state.
    public func endCurrentSession() {
        lock.lock()
        let handlers = Array(activeHandlers.values)
        activeHandlers.removeAll()
        lock.unlock()

        for handler in handlers {
            handler.cancel()
        }
        resetSessionState()
    }

    /// Stops Bonjour advertising, handlers, and the mirror TCP server.
    public func stop() {
        lock.lock()
        let activeListener = listener
        listener = nil
        let handlers = Array(activeHandlers.values)
        activeHandlers.removeAll()
        lock.unlock()

        for handler in handlers {
            handler.cancel()
        }
        activeListener?.cancel()
        resetSessionState()
        AirPlayMirrorServer.shared.shutdown()
        setState(.stopped)
        AppLogger.info("AirPlay receiver stopped", category: .airplay)
    }

    /// stop() then start() for rediscovery after configuration changes.
    public func restart() async throws {
        stop()
        try await start()
    }

    /// Stops audio/timing, resets mirror decrypt/decoder, and clears session context.
    private func resetSessionState() {
        AirPlayAudioServer.shared.stop()
        AirPlayTimingServer.shared.stop()
        AirPlayMirrorServer.shared.resetSession()
        AirPlaySessionContext.shared.deactivate()
        AirPlayMirrorServer.shared.onStreamStarted = { [weak self] in
            self?.mirroringStartedSubject.send("iPhone")
        }
        frameCounter = 0
        latestFrame = nil
        lastReportedOrientation = .portrait
    }

    /// Publishes decoded frames and orientation changes from the H.264 pipeline.
    public func decoder(_: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let orientation: DeviceOrientation = width >= height ? .landscapeLeft : .portrait

        lock.lock()
        frameCounter += 1
        let currentCount = frameCounter
        let shouldLog = currentCount == 1
        let orientationChanged = orientation != lastReportedOrientation
        if orientationChanged {
            lastReportedOrientation = orientation
        }
        lock.unlock()

        if orientationChanged {
            AppLogger.info(
                "AirPlay device orientation → \(orientation.rawValue) (\(width)x\(height))",
                category: .airplay
            )
            orientationSubject.send(orientation)
        }

        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimestamp: presentationTime,
            orientation: orientation,
            frameIndex: currentCount,
            captureTimestamp: .now()
        )

        lock.lock()
        latestFrame = frame
        lock.unlock()

        if shouldLog {
            AppLogger.info("AirPlay video frame #1 ready for UI (\(width)x\(height))", category: .airplay)
        }

        frameSubject.send(frame)
    }

    /// Most recently decoded video frame for UI snapshots, if any.
    public func latestVideoFrame() -> VideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    /// Logs decoder failures; does not tear down the AirPlay session.
    public func decoder(_: VideoDecoder, didFailWithError error: Error) {
        AppLogger.error("Video decoder error: \(error.localizedDescription)", category: .airplay)
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Error>

    /// Wraps a throwing continuation so ready/failed/cancelled resume at most once.
    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    /// Resumes successfully if not already finished.
    func complete() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume()
    }

    /// Resumes with `error` if not already finished.
    func fail(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(throwing: error)
    }
}
