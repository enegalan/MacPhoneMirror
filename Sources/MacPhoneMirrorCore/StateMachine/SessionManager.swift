import Combine
import CoreGraphics
import Foundation

public final class SessionManager: ObservableObject, @unchecked Sendable {
    public static let shared = SessionManager()

    @Published public var state: ConnectionState = .discovering
    @Published public var sessions: [MirrorSession] = []
    @Published public var orientation: DeviceOrientation = .portrait
    @Published public var statistics: StreamStatistics = .init()
    @Published public var isServiceEnabled: Bool = true

    public let sessionWindowOpenPublisher = PassthroughSubject<String, Never>()
    public let sessionWindowClosePublisher = PassthroughSubject<String, Never>()

    private let stateSubject = CurrentValueSubject<ConnectionState, Never>(.discovering)
    private let orientationSubject = CurrentValueSubject<DeviceOrientation, Never>(.portrait)
    private let statisticsSubject = CurrentValueSubject<StreamStatistics, Never>(StreamStatistics())

    private var sessionsByID: [String: MirrorSession] = [:]
    private var sessionReceivers: [String: ScreenMirrorReceiver] = [:]
    private var sessionTransports: [String: PhoneInputTransport] = [:]
    private var activeSessionID: String?
    private let coordinateMapper: InputCoordinateMapper = StandardCoordinateMapper()
    private let usbDiscovery = USBDeviceDiscovery()
    private var cancellables = Set<AnyCancellable>()
    private let lock = NSLock()
    private var statsTimer: Timer?
    private var isListening = false
    private var connectedUSBDeviceID: String?

    public var statePublisher: AnyPublisher<ConnectionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var orientationPublisher: AnyPublisher<DeviceOrientation, Never> {
        orientationSubject.eraseToAnyPublisher()
    }

    public var statisticsPublisher: AnyPublisher<StreamStatistics, Never> {
        statisticsSubject.eraseToAnyPublisher()
    }

    public var currentReceiver: ScreenMirrorReceiver? {
        lock.lock()
        defer { lock.unlock() }
        if let activeSessionID, let receiver = sessionReceivers[activeSessionID] {
            return receiver
        }
        return sessionReceivers.values.first
    }

    public var activeSession: MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        if let activeSessionID, let session = sessionsByID[activeSessionID] {
            return session
        }
        return sessionsByID.values.first
    }

    public var hasActiveSessions: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !sessionsByID.isEmpty
    }

    public init() {
        isServiceEnabled = UserDefaults.standard.object(forKey: "airplay.serviceEnabled") as? Bool ?? true

        stateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
            .store(in: &cancellables)

        orientationSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newOrientation in
                self?.orientation = newOrientation
            }
            .store(in: &cancellables)

        statisticsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStats in
                self?.statistics = newStats
            }
            .store(in: &cancellables)

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
                self?.setOrientation(orientation, sessionID: self?.airPlaySessionIDs().first)
            }
            .store(in: &cancellables)

        startStatsTimer()
    }

    private func startStatsTimer() {
        DispatchQueue.main.async {
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let stats = PerformanceMonitor.shared.currentStatistics()
                self?.statisticsSubject.send(stats)
            }
        }
    }

    private func setState(_ newState: ConnectionState) {
        lock.lock()
        stateSubject.send(newState)
        lock.unlock()
    }

    private func syncPublishedSessions() {
        lock.lock()
        let list = Array(sessionsByID.values).sorted { $0.device.name < $1.device.name }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.sessions = list
        }
    }

    private func airPlaySessionIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID.values
            .filter { $0.device.connectionType == .wifi }
            .map(\.id)
    }

    private func firstRemainingSession() -> MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID.values.first
    }

    public func session(id: String) -> MirrorSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByID[id]
    }

    public func receiver(for sessionID: String) -> ScreenMirrorReceiver? {
        lock.lock()
        defer { lock.unlock() }
        return sessionReceivers[sessionID]
    }

    @discardableResult
    public func beginMirroringSession(
        device: PhoneDevice,
        receiver: ScreenMirrorReceiver,
        transport: PhoneInputTransport,
        replaceExistingAirPlay: Bool = true
    ) -> String {
        if replaceExistingAirPlay {
            replaceAirPlaySessionsIfNeeded(keepingDeviceID: device.id)
        }

        let sessionID = device.id
        let session = MirrorSession(id: sessionID, device: device, orientation: .portrait)

        lock.lock()
        if let previous = sessionReceivers[sessionID], previous !== receiver {
            let wasAirPlay = previous === NetworkStreamReceiver.shared
            sessionTransports[sessionID]?.disconnect()
            if !wasAirPlay {
                previous.stop()
            }
            sessionWindowClosePublisher.send(sessionID)
        }
        sessionsByID[sessionID] = session
        sessionReceivers[sessionID] = receiver
        sessionTransports[sessionID] = transport
        activeSessionID = sessionID
        lock.unlock()

        syncPublishedSessions()
        setOrientation(.portrait, sessionID: sessionID)
        setState(.mirroring(device))
        sessionWindowOpenPublisher.send(sessionID)
        AppLogger.info("Mirror session opened: \(device.name) (\(sessionID))", category: .session)
        return sessionID
    }

    private func replaceAirPlaySessionsIfNeeded(keepingDeviceID: String) {
        lock.lock()
        let existingIDs = sessionsByID.values
            .filter { $0.device.connectionType == .wifi && $0.id != keepingDeviceID }
            .map(\.id)
        lock.unlock()

        for id in existingIDs {
            tearDownSession(id: id, stopReceiver: false, publishClose: true)
        }
    }

    private func tearDownSession(id: String, stopReceiver: Bool, publishClose: Bool) {
        lock.lock()
        let receiver = sessionReceivers.removeValue(forKey: id)
        let transport = sessionTransports.removeValue(forKey: id)
        sessionsByID.removeValue(forKey: id)
        if activeSessionID == id {
            activeSessionID = sessionReceivers.keys.first
        }
        let isAirPlay = receiver === NetworkStreamReceiver.shared
        lock.unlock()

        transport?.disconnect()
        if stopReceiver, let receiver, !isAirPlay {
            receiver.stop()
        }

        syncPublishedSessions()
        if publishClose {
            sessionWindowClosePublisher.send(id)
        }
    }

    private func getTransport(for sessionID: String?) -> PhoneInputTransport? {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID {
            return sessionTransports[sessionID]
        }
        return activeSessionID.flatMap { sessionTransports[$0] } ?? sessionTransports.values.first
    }

    private func markListeningStarted() {
        lock.lock()
        isListening = true
        lock.unlock()
    }

    private func isAlreadyListening() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isListening
    }

    public func startListening() async {
        if isAlreadyListening() {
            return
        }

        guard isServiceEnabled else {
            AppLogger.info("AirPlay service is disabled; skipping start.", category: .session)
            return
        }

        setState(.discovering)
        PermissionManager.shared.requestLocalNetworkPermission()

        do {
            try await NetworkStreamReceiver.shared.start()
            markListeningStarted()
            AppLogger.info("AirPlay receiver ready. Waiting for iPhone to connect.", category: .session)
        } catch {
            let message = "Could not start AirPlay receiver: \(error.localizedDescription)"
            AppLogger.error(message, category: .session)
            setState(.failed(message))
            return
        }

        setupUSBAutoConnect()
    }

    private func setupUSBAutoConnect() {
        usbDiscovery.start()
        usbDiscovery.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }

                if let usbDevice = devices.first {
                    if connectedUSBDeviceID != usbDevice.id {
                        connectedUSBDeviceID = usbDevice.id
                        Task { await self.connectUSB(usbDevice) }
                    }
                } else {
                    connectedUSBDeviceID = nil
                }
            }
            .store(in: &cancellables)
    }

    private func handleIncomingAirPlay(from deviceName: String) {
        let device = PhoneDevice(
            id: "airplay-\(deviceName)",
            name: deviceName,
            connectionType: .wifi,
            isPairedForControl: false
        )

        let transport = SimulatedInputTransport()
        beginMirroringSession(
            device: device,
            receiver: NetworkStreamReceiver.shared,
            transport: transport,
            replaceExistingAirPlay: true
        )

        Task {
            let bluetoothTransport = BluetoothHIDTransport()
            do {
                try await bluetoothTransport.connect()
                replaceSimulatedTransportIfNeeded(sessionID: device.id, with: bluetoothTransport)
            } catch {
                AppLogger.warning("Bluetooth input unavailable: \(error.localizedDescription)", category: .session)
            }
        }
    }

    private func replaceSimulatedTransportIfNeeded(sessionID: String, with transport: PhoneInputTransport) {
        lock.lock()
        if sessionTransports[sessionID] is SimulatedInputTransport {
            sessionTransports[sessionID] = transport
        } else {
            transport.disconnect()
        }
        lock.unlock()
    }

    private func handleAirPlaySessionEnded() {
        for id in airPlaySessionIDs() {
            tearDownSession(id: id, stopReceiver: false, publishClose: true)
        }

        PerformanceMonitor.shared.reset()
        AirPlayPairingState.shared.clearPIN()
        setOrientation(.portrait)

        if let remaining = firstRemainingSession() {
            setState(.mirroring(remaining.device))
            setOrientation(remaining.orientation, sessionID: remaining.id)
        } else {
            setState(.discovering)
        }

        AppLogger.info("AirPlay mirroring ended. Waiting for next connection.", category: .session)
    }

    private func connectUSB(_ device: PhoneDevice) async {
        setState(.connecting(device))
        AppLogger.info("USB iPhone detected: \(device.name)", category: .session)

        let receiver = AVFoundationUSBReceiver(deviceID: device.id)
        let inputTransport = BluetoothHIDTransport()

        do {
            try await receiver.start()
            try await inputTransport.connect()
            beginMirroringSession(
                device: device,
                receiver: receiver,
                transport: inputTransport,
                replaceExistingAirPlay: false
            )
            AppLogger.info("USB mirroring started for \(device.name)", category: .session)
        } catch {
            receiver.stop()
            inputTransport.disconnect()
            connectedUSBDeviceID = nil

            let message = "Could not start USB mirroring for \(device.name): \(error.localizedDescription)"
            AppLogger.error(message, category: .session)
            setState(.discovering)
        }
    }

    public func disconnect(sessionID: String) {
        lock.lock()
        let receiver = sessionReceivers[sessionID]
        let isAirPlay = receiver === NetworkStreamReceiver.shared
        lock.unlock()

        tearDownSession(id: sessionID, stopReceiver: true, publishClose: true)

        if isAirPlay {
            NetworkStreamReceiver.shared.endCurrentSession()
            PerformanceMonitor.shared.reset()
            AirPlayPairingState.shared.clearPIN()
        }

        if let remaining = firstRemainingSession() {
            setState(.mirroring(remaining.device))
            setOrientation(remaining.orientation, sessionID: remaining.id)
        } else {
            setOrientation(.portrait)
            setState(.discovering)
            connectedUSBDeviceID = nil
            AppLogger.info("All mirror sessions closed.", category: .session)
        }
    }

    public func disconnect() {
        lock.lock()
        let ids = Array(sessionsByID.keys)
        lock.unlock()
        for id in ids {
            disconnect(sessionID: id)
        }
        if ids.isEmpty {
            setState(.discovering)
        }
    }

    // MARK: - Service Management

    public func setServiceEnabled(_ enabled: Bool) {
        guard enabled != isServiceEnabled else { return }
        isServiceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "airplay.serviceEnabled")

        if enabled {
            Task { await startListening() }
        } else {
            NetworkStreamReceiver.shared.stop()
            disconnect()
            AppLogger.info("AirPlay service disabled by user", category: .session)
        }
    }

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

    public func setOrientation(_ newOrientation: DeviceOrientation, sessionID: String? = nil) {
        lock.lock()
        let targetID = sessionID ?? activeSessionID ?? sessionsByID.keys.first
        guard let targetID, var session = sessionsByID[targetID] else {
            lock.unlock()
            if orientation != newOrientation {
                orientationSubject.send(newOrientation)
            }
            return
        }

        let shouldUpdateGlobal = targetID == activeSessionID || sessionsByID.count == 1
        let changed = session.orientation != newOrientation
        if changed {
            session.orientation = newOrientation
            sessionsByID[targetID] = session
        }
        lock.unlock()

        if changed {
            syncPublishedSessions()
            AppLogger.info("Device orientation updated: \(newOrientation.rawValue)", category: .session)
        }

        if shouldUpdateGlobal, orientation != newOrientation {
            orientationSubject.send(newOrientation)
        }
    }

    public func sendInputEvent(_ event: PhoneInputEvent, sessionID: String? = nil) async throws {
        if let transport = getTransport(for: sessionID) {
            try await transport.send(event)
        }
    }

    public func handleMouseClick(
        at viewportPoint: CGPoint,
        viewportSize: CGSize,
        sessionID: String? = nil
    ) async {
        let resolved = sessionID.flatMap { self.session(id: $0) } ?? (sessionID == nil ? activeSession : nil)
        guard let session = resolved else { return }

        if let normPoint = coordinateMapper.map(
            point: viewportPoint,
            in: viewportSize,
            device: session.device,
            orientation: session.orientation
        ) {
            try? await sendInputEvent(.pointerTo(normalizedX: normPoint.x, normalizedY: normPoint.y), sessionID: session.id)
            try? await sendInputEvent(.pointerDown(button: .left), sessionID: session.id)
            try? await Task.sleep(nanoseconds: 50_000_000)
            try? await sendInputEvent(.pointerUp(button: .left), sessionID: session.id)
        }
    }
}
