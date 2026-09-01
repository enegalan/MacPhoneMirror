import Combine
import CoreMedia
import CoreVideo
import Foundation
import Network

public final class NetworkStreamReceiver: NSObject, ScreenMirrorReceiver, VideoDecoderDelegate, @unchecked Sendable {
    public static let shared = NetworkStreamReceiver()

    public let mirroringStartedPublisher = PassthroughSubject<String, Never>()
    public let sessionEndedPublisher = PassthroughSubject<Void, Never>()
    public let orientationPublisher = PassthroughSubject<DeviceOrientation, Never>()

    private let decoder = VideoDecoder()
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

    override private init() {
        super.init()
        decoder.delegate = self
        AirPlayMirrorServer.shared.configureVideoPipeline(delegate: self)
        AirPlayMirrorServer.shared.onStreamStarted = { [weak self] in
            self?.mirroringStartedPublisher.send("iPhone")
        }
    }

    private func setState(_ newState: ReceiverState) {
        lock.lock()
        _state = newState
        lock.unlock()
    }

    private func isRunningState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .running = _state {
            return true
        }
        return false
    }

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

    public func start() async throws {
        if shouldSkipStart() {
            return
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
            let resumeOnce = ResumeOnce(continuation: continuation)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

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

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            self.lock.lock()
            self.listener?.cancel()
            self.listener = listener
            self.lock.unlock()

            listener.start(queue: self.queue)
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        AppLogger.info("Incoming AirPlay connection from \(connection.endpoint)", category: .network)

        let handler = AirPlayConnectionHandler(connection: connection, identity: identity, queue: queue)
        handler.controlPort = advertisedPort
        handler.onMirroringStarted = { [weak self] deviceName in
            self?.mirroringStartedPublisher.send(deviceName)
        }
        handler.onSessionEnded = { [weak self] in
            self?.handleConnectionEnded(connectionID)
        }

        lock.lock()
        activeHandlers[connectionID] = handler
        lock.unlock()

        handler.start()
    }

    private func handleConnectionEnded(_ connectionID: ObjectIdentifier) {
        lock.lock()
        activeHandlers.removeValue(forKey: connectionID)
        let hasActiveHandlers = !activeHandlers.isEmpty
        lock.unlock()

        if !hasActiveHandlers {
            sessionEndedPublisher.send(())
        }
    }

    public func endCurrentSession() {
        lock.lock()
        activeHandlers.removeAll()
        lock.unlock()
        AirPlayMirrorServer.shared.resetSession()
        AirPlaySessionContext.shared.deactivate()
        AirPlayMirrorServer.shared.onStreamStarted = { [weak self] in
            self?.mirroringStartedPublisher.send("iPhone")
        }
        decoder.invalidateSession()
        frameCounter = 0
        latestFrame = nil
        lastReportedOrientation = .portrait
    }

    public func stop() {
        lock.lock()
        let activeListener = listener
        listener = nil
        activeHandlers.removeAll()
        lock.unlock()

        activeListener?.cancel()
        decoder.invalidateSession()
        setState(.stopped)
        AppLogger.info("AirPlay receiver stopped", category: .airplay)
    }

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
            orientationPublisher.send(orientation)
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

    public func latestVideoFrame() -> VideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    public func decoder(_: VideoDecoder, didFailWithError error: Error) {
        AppLogger.error("Video decoder error: \(error.localizedDescription)", category: .airplay)
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Error>

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func complete() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume()
    }

    func fail(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(throwing: error)
    }
}
