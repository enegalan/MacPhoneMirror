import Foundation
import Combine
import CoreGraphics

public final class SessionManager: ObservableObject, @unchecked Sendable {
    public static let shared = SessionManager()

    @Published public var state: ConnectionState = .discovering
    @Published public var orientation: DeviceOrientation = .portrait
    @Published public var statistics: StreamStatistics = StreamStatistics()

    private let stateSubject = CurrentValueSubject<ConnectionState, Never>(.discovering)
    private let orientationSubject = CurrentValueSubject<DeviceOrientation, Never>(.portrait)
    private let statisticsSubject = CurrentValueSubject<StreamStatistics, Never>(StreamStatistics())

    private var activeReceiver: ScreenMirrorReceiver?
    private var activeInputTransport: PhoneInputTransport?
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
        return activeReceiver
    }

    public init() {
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
                self?.handleSessionEnded()
            }
            .store(in: &cancellables)

        NetworkStreamReceiver.shared.orientationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orientation in
                self?.setOrientation(orientation)
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

    private func setSession(receiver: ScreenMirrorReceiver, transport: PhoneInputTransport, device: PhoneDevice) {
        lock.lock()
        self.activeReceiver = receiver
        self.activeInputTransport = transport
        self.stateSubject.send(.mirroring(device))
        lock.unlock()
    }

    private func getTransports() -> (PhoneInputTransport?, ScreenMirrorReceiver?) {
        lock.lock()
        defer { lock.unlock() }
        return (activeInputTransport, activeReceiver)
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
                guard !self.state.isConnectedOrMirroring else { return }

                if let usbDevice = devices.first {
                    if self.connectedUSBDeviceID != usbDevice.id {
                        self.connectedUSBDeviceID = usbDevice.id
                        Task { await self.connectUSB(usbDevice) }
                    }
                } else {
                    self.connectedUSBDeviceID = nil
                }
            }
            .store(in: &cancellables)
    }

    private func handleIncomingAirPlay(from deviceName: String) {
        guard !state.isConnectedOrMirroring else { return }

        let device = PhoneDevice(
            id: "airplay-\(deviceName)",
            name: deviceName,
            connectionType: .wifi,
            isPairedForControl: false
        )

        let transport = SimulatedInputTransport()
        setSession(receiver: NetworkStreamReceiver.shared, transport: transport, device: device)
        AppLogger.info("AirPlay session started for \(deviceName)", category: .session)

        Task {
            let bluetoothTransport = BluetoothHIDTransport()
            do {
                try await bluetoothTransport.connect()
                replaceSimulatedTransportIfNeeded(with: bluetoothTransport)
            } catch {
                AppLogger.warning("Bluetooth input unavailable: \(error.localizedDescription)", category: .session)
            }
        }
    }

    private func replaceSimulatedTransportIfNeeded(with transport: PhoneInputTransport) {
        lock.lock()
        if activeInputTransport is SimulatedInputTransport {
            activeInputTransport = transport
        } else {
            transport.disconnect()
        }
        lock.unlock()
    }

    private func handleSessionEnded() {
        guard state.isConnectedOrMirroring else {
            setState(.discovering)
            return
        }

        lock.lock()
        let receiver = activeReceiver
        let isAirPlayReceiver = receiver === NetworkStreamReceiver.shared
        activeReceiver = nil
        activeInputTransport?.disconnect()
        activeInputTransport = nil
        lock.unlock()

        if !isAirPlayReceiver {
            receiver?.stop()
        } else {
            NetworkStreamReceiver.shared.endCurrentSession()
        }

        PerformanceMonitor.shared.reset()
        AirPlayPairingState.shared.clearPIN()
        setOrientation(.portrait)
        setState(.discovering)
        AppLogger.info("Mirroring session ended. Waiting for next AirPlay connection.", category: .session)
    }

    private func connectUSB(_ device: PhoneDevice) async {
        setState(.connecting(device))
        AppLogger.info("USB iPhone detected: \(device.name)", category: .session)

        let receiver = AVFoundationUSBReceiver(deviceID: device.id)
        let inputTransport = BluetoothHIDTransport()

        do {
            try await receiver.start()
            try await inputTransport.connect()
            setSession(receiver: receiver, transport: inputTransport, device: device)
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

    public func disconnect() {
        handleSessionEnded()
    }

    public func setOrientation(_ newOrientation: DeviceOrientation) {
        guard orientation != newOrientation else { return }
        lock.lock()
        orientationSubject.send(newOrientation)
        lock.unlock()
        AppLogger.info("Device orientation updated: \(newOrientation.rawValue)", category: .session)
    }

    public func sendInputEvent(_ event: PhoneInputEvent) async throws {
        let (transport, _) = getTransports()

        if let transport = transport {
            try await transport.send(event)
        }
    }

    public func handleMouseClick(at viewportPoint: CGPoint, viewportSize: CGSize) async {
        guard let device = state.activeDevice else { return }

        if let normPoint = coordinateMapper.map(point: viewportPoint, in: viewportSize, device: device, orientation: orientation) {
            try? await sendInputEvent(.pointerTo(normalizedX: normPoint.x, normalizedY: normPoint.y))
            try? await sendInputEvent(.pointerDown(button: .left))
            try? await Task.sleep(nanoseconds: 50_000_000)
            try? await sendInputEvent(.pointerUp(button: .left))
        }
    }
}
