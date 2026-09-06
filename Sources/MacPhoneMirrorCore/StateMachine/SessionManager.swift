import Combine
import CoreGraphics
import Foundation

/// Facade: AirPlay listen toggle, USB auto-connect, session open/close, input fan-out.
/// UI observes @Published state/sessions; mirror windows open via publishers.
/// AirPlay video can start before HID is ready — uses SimulatedInputTransport until connect() succeeds.
// swiftlint:disable:next type_body_length
public final class SessionManager: ObservableObject, @unchecked Sendable {
    public static let shared = SessionManager()

    @Published public var state: ConnectionState = .discovering
    @Published public var sessions: [MirrorSession] = []
    @Published public var orientation: DeviceOrientation = .portrait
    @Published public var isServiceEnabled: Bool = true

    private let sessionWindowOpenSubject = PassthroughSubject<String, Never>()
    private let sessionWindowCloseSubject = PassthroughSubject<String, Never>()
    private let store = MirrorSessionStore()
    private let service = AirPlayServiceController()
    private let usbCoordinator = USBAutoConnectCoordinator()
    private lazy var inputRouter = SessionInputRouter(
        sessionLookup: { [weak self] id in self?.store.session(id: id) },
        activeSessionID: { [weak self] in
            self?.store.activeSession?.id
        },
        send: { [weak self] event, sessionID in
            try await self?.sendInputEvent(
                event,
                sessionID: sessionID
            )
        }
    )
    private var cancellables = Set<AnyCancellable>()

    public var sessionWindowOpenPublisher: AnyPublisher<String, Never> {
        sessionWindowOpenSubject.eraseToAnyPublisher()
    }

    public var sessionWindowClosePublisher: AnyPublisher<String, Never> {
        sessionWindowCloseSubject.eraseToAnyPublisher()
    }

    public var activeSession: MirrorSession? {
        store.activeSession
    }

    public var hasActiveSessions: Bool {
        store.hasActiveSessions
    }

    /// Wires store callbacks, USB auto-connect, and AirPlay Combine sinks onto the main queue.
    public init() {
        let serviceKey = AppPreferences.Key.airPlayServiceEnabled
        isServiceEnabled = UserDefaults.standard.object(forKey: serviceKey) as? Bool ?? true

        store.onSessionsChanged = { [weak self] in
            self?.syncPublishedSessions()
        }
        store.onWindowClose = { [weak self] id in
            self?.sessionWindowCloseSubject.send(id)
        }

        usbCoordinator.onDeviceAppeared = { [weak self] device in
            guard let self else { return }
            Task { await self.connectUSB(device) }
        }
        usbCoordinator.onDeviceDisappeared = { [weak self] deviceID in
            self?.disconnect(sessionID: deviceID)
            self?.usbCoordinator.clearConnectedDevice()
        }

        NetworkStreamReceiver.shared.mirroringStartedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceName in
                self?.handleIncomingAirPlay(from: deviceName)
            }
            .store(in: &cancellables)

        NetworkStreamReceiver.shared.sessionEndedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleAirPlaySessionEnded()
            }
            .store(in: &cancellables)

        NetworkStreamReceiver.shared.orientationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orientation in
                self?.setOrientation(orientation, sessionID: self?.store.airPlaySessionIDs().first)
            }
            .store(in: &cancellables)
    }

    /// Publishes connection state on the main thread for SwiftUI observation.
    private func setState(_ newState: ConnectionState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        }
    }

    /// Publishes global orientation on the main thread; skips no-op updates.
    private func publishOrientation(_ newOrientation: DeviceOrientation) {
        if Thread.isMainThread {
            guard orientation != newOrientation else { return }
            orientation = newOrientation
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, orientation != newOrientation else { return }
                orientation = newOrientation
            }
        }
    }

    /// Mirrors store.sortedSessions into @Published sessions on the main queue.
    private func syncPublishedSessions() {
        let list = store.sortedSessions
        DispatchQueue.main.async { [weak self] in
            self?.sessions = list
        }
    }

    /// Looks up a session by id without mutating store state.
    public func session(id: String) -> MirrorSession? {
        store.session(id: id)
    }

    /// Returns the video receiver bound to a session (AirPlay shared or USB-owned).
    public func receiver(for sessionID: String) -> ScreenMirrorReceiver? {
        store.receiver(for: sessionID)
    }

    /// Installs a session, opens its mirror window, and sets state to mirroring.
    /// When replaceExistingAirPlay is true, tears down other Wi-Fi sessions first.
    @discardableResult
    public func beginMirroringSession(
        device: PhoneDevice,
        receiver: ScreenMirrorReceiver,
        transport: PhoneInputTransport,
        replaceExistingAirPlay: Bool = true
    ) -> String {
        if replaceExistingAirPlay {
            for id in store.replaceAirPlaySessionIDs(keepingDeviceID: device.id) {
                store.tearDown(id: id, stopReceiver: false, publishClose: true)
            }
        }

        let sessionID = device.id
        let session = MirrorSession(device: device, id: sessionID, orientation: .portrait)
        _ = store.install(session: session, receiver: receiver, transport: transport)

        setOrientation(.portrait, sessionID: sessionID)
        setState(.mirroring(device))
        sessionWindowOpenSubject.send(sessionID)
        AppLogger.info("Mirror session opened: \(device.name) (\(sessionID))", category: .session)
        return sessionID
    }

    /// Bumps the AirPlay generation and starts advertising if the service is enabled.
    public func startListening() async {
        let generation = service.bumpGeneration()
        await startListening(generation: generation)
    }

    /// Generation-guarded AirPlay + HID + USB discovery start; aborts if toggled off mid-await.
    private func startListening(generation: UInt64) async {
        guard isServiceEnabled, service.isCurrentGeneration(generation) else {
            AppLogger.info("AirPlay service is disabled; skipping start.", category: .session)
            return
        }

        if service.isAlreadyListening(), NetworkStreamReceiver.shared.isAdvertising {
            return
        }

        setState(.discovering)
        PermissionManager.shared.requestLocalNetworkPermission()
        PermissionManager.shared.requestBluetoothPermission()

        do {
            try await NetworkStreamReceiver.shared.start()
            guard isServiceEnabled, service.isCurrentGeneration(generation) else {
                NetworkStreamReceiver.shared.stop()
                service.markListeningStopped()
                AppLogger.info("AirPlay start aborted — service toggled off mid-start", category: .session)
                return
            }
            service.markListeningStarted()
            AppLogger.info("AirPlay receiver ready. Waiting for iPhone to connect.", category: .session)
        } catch {
            guard service.isCurrentGeneration(generation) else {
                AppLogger.info("Ignoring stale AirPlay start failure after newer toggle", category: .session)
                return
            }
            service.markListeningStopped()
            let message = "Could not start AirPlay receiver: \(error.localizedDescription)"
            AppLogger.error(message, category: .session)
            setState(.failed(message))
            return
        }

        guard service.isCurrentGeneration(generation), isServiceEnabled else { return }

        Task {
            do {
                try await BluetoothHIDTransport.shared.connect()
                AppLogger.info("Bluetooth HID ready for AssistiveTouch pairing", category: .bluetooth)
            } catch {
                AppLogger.warning("Bluetooth HID unavailable: \(error.localizedDescription)", category: .bluetooth)
            }
        }

        usbCoordinator.start()
    }

    /// Stops AirPlay advertising, HID, and all sessions after invalidating the start generation.
    private func stopListening() {
        _ = service.bumpGeneration()
        service.markListeningStopped()
        NetworkStreamReceiver.shared.stop()
        BluetoothHIDTransport.shared.stopAdvertising()
        disconnect()
        setState(.disconnected)
        AppLogger.info("AirPlay service disabled by user", category: .session)
    }

    /// Opens an AirPlay mirror session; uses SimulatedInputTransport until HID connect succeeds.
    private func handleIncomingAirPlay(from deviceName: String) {
        let device = PhoneDevice(
            name: deviceName,
            id: "airplay-active",
            connectionType: .wifi,
            isPairedForControl: false
        )

        // Video (AirPlay) and control (BLE HID) are independent channels. Start mirroring
        // immediately; use SimulatedInputTransport until HID advertising/subscribers exist.
        let hid = BluetoothHIDTransport.shared
        beginMirroringSession(
            device: device,
            receiver: NetworkStreamReceiver.shared,
            transport: hid.isConnected ? hid : SimulatedInputTransport(),
            replaceExistingAirPlay: true
        )

        Task {
            do {
                try await hid.connect()
                // Swap the no-op fallback for the real peripheral once connect() succeeds.
                store.replaceSimulatedTransportIfNeeded(sessionID: device.id, with: hid)
            } catch {
                AppLogger.warning("Bluetooth input unavailable: \(error.localizedDescription)", category: .session)
            }
        }
    }

    /// Tears down Wi-Fi sessions on AirPlay end; restores USB session state if any remain.
    private func handleAirPlaySessionEnded() {
        for id in store.airPlaySessionIDs() {
            store.tearDown(id: id, stopReceiver: false, publishClose: true)
        }

        AirPlayPairingState.shared.clearPIN()
        setOrientation(.portrait)

        if let remaining = store.firstRemainingSession() {
            setState(.mirroring(remaining.device))
            setOrientation(remaining.orientation, sessionID: remaining.id)
        } else {
            setState(.discovering)
        }

        AppLogger.info("AirPlay mirroring ended. Waiting for next connection.", category: .session)
    }

    /// Starts USB capture and a non-replacing mirror session; clears USB tracking on failure.
    private func connectUSB(_ device: PhoneDevice) async {
        setState(.connecting(device))
        AppLogger.info("USB iPhone detected: \(device.name)", category: .session)

        let receiver = AVFoundationUSBReceiver(deviceID: device.id)
        let inputTransport = BluetoothHIDTransport.shared

        do {
            try await receiver.start()
            beginMirroringSession(
                device: device,
                receiver: receiver,
                transport: inputTransport,
                replaceExistingAirPlay: false
            )
            AppLogger.info("USB mirroring started for \(device.name)", category: .session)
            Task {
                do {
                    try await inputTransport.connect()
                } catch {
                    AppLogger.warning(
                        "Bluetooth HID unavailable for USB session: \(error.localizedDescription)",
                        category: .bluetooth
                    )
                }
            }
        } catch {
            receiver.stop()
            usbCoordinator.clearConnectedDevice()

            let message = "Could not start USB mirroring for \(device.name): \(error.localizedDescription)"
            AppLogger.error(message, category: .session)
            setState(.discovering)
        }
    }

    /// Closes one session; ends AirPlay network session if needed and updates global state.
    public func disconnect(sessionID: String) {
        let isAirPlay = store.isAirPlayReceiver(sessionID: sessionID)
        store.tearDown(id: sessionID, stopReceiver: true, publishClose: true)

        if isAirPlay {
            NetworkStreamReceiver.shared.endCurrentSession()
            AirPlayPairingState.shared.clearPIN()
        }

        if let remaining = store.firstRemainingSession() {
            setState(.mirroring(remaining.device))
            setOrientation(remaining.orientation, sessionID: remaining.id)
        } else {
            setOrientation(.portrait)
            setState(.discovering)
            usbCoordinator.clearConnectedDevice()
            AppLogger.info("All mirror sessions closed.", category: .session)
        }
    }

    /// Closes every open session; falls back to discovering when none existed.
    public func disconnect() {
        let ids = store.allSessionIDs
        for id in ids {
            disconnect(sessionID: id)
        }
        if ids.isEmpty {
            setState(.discovering)
        }
    }

    /// Persists AirPlay service enablement and starts or stops listening accordingly.
    public func setServiceEnabled(_ enabled: Bool) {
        guard enabled != isServiceEnabled else { return }
        isServiceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppPreferences.Key.airPlayServiceEnabled)

        if enabled {
            let generation = service.bumpGeneration()
            Task { await startListening(generation: generation) }
        } else {
            stopListening()
        }
    }

    /// Updates the advertised AirPlay name and restarts the receiver if currently listening.
    public func updateServiceName(_ newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AirPlayTXTRecordBuilder.serviceName else { return }
        AirPlayTXTRecordBuilder.serviceName = trimmed

        if isServiceEnabled, NetworkStreamReceiver.shared.isAdvertising {
            do {
                try await NetworkStreamReceiver.shared.restart()
                AppLogger.info("AirPlay service restarted with name: \(trimmed)", category: .session)
            } catch {
                AppLogger.error("Failed to restart AirPlay service: \(error.localizedDescription)", category: .session)
            }
        }
    }

    /// Updates session (and optionally global) orientation via the store.
    public func setOrientation(_ newOrientation: DeviceOrientation, sessionID: String? = nil) {
        let result = store.updateOrientation(newOrientation, sessionID: sessionID)
        if result.targetMissing {
            publishOrientation(newOrientation)
            return
        }
        if result.changed {
            AppLogger.info("Device orientation updated: \(newOrientation.rawValue)", category: .session)
        }
        if result.shouldUpdateGlobal {
            publishOrientation(newOrientation)
        }
    }

    /// Forwards a control event to the session's input transport (nil id → active session).
    public func sendInputEvent(_ event: PhoneInputEvent, sessionID: String? = nil) async throws {
        if let transport = store.transport(for: sessionID) {
            try await transport.send(event)
        }
    }

    /// Maps a viewport pointer-down into HID events for the target session.
    public func handlePointerDown(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String? = nil
    ) async {
        await inputRouter.handlePointerDown(at: viewportPoint, viewportSize: viewportSize, sessionID: sessionID)
    }

    /// Maps a viewport pointer-move into HID events for the target session.
    public func handlePointerMove(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String? = nil
    ) async {
        await inputRouter.handlePointerMove(at: viewportPoint, viewportSize: viewportSize, sessionID: sessionID)
    }

    /// Maps a viewport pointer-up into HID events for the target session.
    public func handlePointerUp(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String? = nil
    ) async {
        await inputRouter.handlePointerUp(at: viewportPoint, viewportSize: viewportSize, sessionID: sessionID)
    }
}
