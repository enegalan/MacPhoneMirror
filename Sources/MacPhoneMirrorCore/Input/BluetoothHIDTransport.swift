import CoreBluetooth
import Foundation

public final class BluetoothHIDTransport: NSObject, PhoneInputTransport, @unchecked Sendable {
    public static let shared = BluetoothHIDTransport()

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAdvertising || !_subscribedCentrals.isEmpty
    }

    public var transportName: String {
        "Bluetooth HID (AssistiveTouch)"
    }

    public var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_subscribedCentrals.isEmpty
    }

    private var peripheralManager: CBPeripheralManager?
    private var mouseReportChar: CBMutableCharacteristic?
    private var keyboardReportChar: CBMutableCharacteristic?
    private var consumerReportChar: CBMutableCharacteristic?
    private var bootMouseChar: CBMutableCharacteristic?
    private var bootKeyboardChar: CBMutableCharacteristic?
    private var batteryLevelChar: CBMutableCharacteristic?

    private var _isAdvertising = false
    private var _wantsAdvertising = false
    private var _servicesInstalled = false
    private var activeButtons: UInt8 = 0
    private var readyToNotify = true
    private var pendingNotify: (Data, CBMutableCharacteristic)?
    private var subscribedCentrals: [UUID: CBCentral] = [:]
    private var _subscribedCentrals: Set<UUID> = []
    private var cachedMouse = Data([0, 0, 0, 0, 0, 0])
    private var cachedKeyboard = Data([0, 0, 0, 0, 0, 0, 0, 0])
    private var cachedConsumer = Data([0, 0])
    private var lastAbsX: UInt16 = 0
    private var lastAbsY: UInt16 = 0
    /// Relative pointer deltas → absolute axis steps (HID units per “point”).
    private let relativeMoveScale: Double = 48

    private let lock = NSLock()
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    private let queue = DispatchQueue(label: "com.macphonemirror.hid", qos: .userInitiated)

    override public init() {
        super.init()
    }

    public func connect() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.connectOnce() }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw NSError(
                    domain: AppInfo.name,
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: "Bluetooth HID advertising timed out. Grant Bluetooth permission and ensure Bluetooth is On."]
                )
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func connectOnce() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            _wantsAdvertising = true
            if _isAdvertising {
                lock.unlock()
                continuation.resume()
                return
            }
            connectWaiters.append(continuation)
            let needsStart = peripheralManager == nil
            lock.unlock()

            if needsStart {
                queue.async { [weak self] in
                    guard let self else { return }
                    AppLogger.info("Creating Bluetooth HID peripheral manager", category: .bluetooth)
                    peripheralManager = CBPeripheralManager(
                        delegate: self,
                        queue: queue,
                        options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
                    )
                }
            } else {
                queue.async { [weak self] in
                    self?.ensureAdvertising()
                }
            }
        }
    }

    public func disconnect() {
        // Shared lifecycle: keep advertising so AssistiveTouch stays paired across sessions.
        // Call stopAdvertising() when the AirPlay service is disabled.
    }

    public func stopAdvertising() {
        lock.lock()
        _wantsAdvertising = false
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            peripheralManager?.stopAdvertising()
            lock.lock()
            _isAdvertising = false
            lock.unlock()
            AppLogger.info("Bluetooth HID advertising stopped", category: .bluetooth)
        }
    }

    public func send(_ event: PhoneInputEvent) async throws {
        guard isConnected else {
            throw NSError(
                domain: AppInfo.name,
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Bluetooth HID is not advertising. Enable Bluetooth and pair via AssistiveTouch."]
            )
        }

        if !hasSubscribers {
            AppLogger.debug("HID event dropped — no iPhone subscribed yet. Pair in AssistiveTouch → Devices.", category: .input)
            return
        }

        switch event {
        case let .pointerMove(dx, dy):
            applyRelativeMove(dx: dx, dy: dy, wheel: 0)

        case let .pointerTo(normalizedX, normalizedY):
            movePointerAbsolute(normalizedX: normalizedX, normalizedY: normalizedY)

        case let .pointerDown(button):
            let btn = setButton(button, pressed: true)
            transmitMouseReport(currentAbsoluteReport(buttons: btn))

        case let .pointerUp(button):
            let btn = setButton(button, pressed: false)
            transmitMouseReport(currentAbsoluteReport(buttons: btn))

        case let .scroll(dx, dy):
            applyRelativeMove(dx: dx, dy: 0, wheel: Int8(clamping: Int(dy.rounded())))

        case let .keyDown(keyCode, modifiers):
            transmitKeyboardReport(HIDKeyboardReport(modifiers: modifiers, keyCodes: [keyCode]))

        case .keyUp:
            transmitKeyboardReport(HIDKeyboardReport(modifiers: 0, keyCodes: []))

        case .homeButton:
            try await sendKeyChord(modifiers: KeyModifier.leftGUI.rawValue, keyCode: 0x0B)

        case .appSwitcher:
            try await sendKeyChord(modifiers: KeyModifier.leftGUI.rawValue, keyCode: 0x2B)

        case .lockScreen:
            try await sendConsumerPulse(.power)

        case .controlCenter:
            movePointerAbsolute(normalizedX: 0.92, normalizedY: 0.02)
            try await clickLeft()

        case .notificationCenter:
            movePointerAbsolute(normalizedX: 0.5, normalizedY: 0.02)
            try await clickLeft()

        case .volumeUp:
            try await sendConsumerPulse(.volumeIncrement)

        case .volumeDown:
            try await sendConsumerPulse(.volumeDecrement)

        case .siri:
            try await sendConsumerPulse(.acSearch)

        case let .swipe(direction):
            try await performSwipe(direction)
        }
    }

    // MARK: - Pointer helpers

    private func movePointerAbsolute(normalizedX: Double, normalizedY: Double) {
        let report = HIDMouseReport.fromNormalized(
            buttons: getActiveButtons(),
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )
        lock.lock()
        lastAbsX = report.x
        lastAbsY = report.y
        lock.unlock()
        transmitMouseReport(report)
    }

    private func applyRelativeMove(dx: Double, dy: Double, wheel: Int8) {
        lock.lock()
        let nextX = min(max(Int(lastAbsX) + Int((dx * relativeMoveScale).rounded()), 0), Int(HIDMouseReport.axisMax))
        let nextY = min(max(Int(lastAbsY) + Int((dy * relativeMoveScale).rounded()), 0), Int(HIDMouseReport.axisMax))
        lastAbsX = UInt16(nextX)
        lastAbsY = UInt16(nextY)
        let x = lastAbsX
        let y = lastAbsY
        let btns = activeButtons
        lock.unlock()
        transmitMouseReport(HIDMouseReport(buttons: btns, x: x, y: y, wheel: wheel))
    }

    private func currentAbsoluteReport(buttons: UInt8) -> HIDMouseReport {
        lock.lock()
        defer { lock.unlock() }
        return HIDMouseReport(buttons: buttons, x: lastAbsX, y: lastAbsY, wheel: 0)
    }

    private func clickLeft() async throws {
        let down = setButton(.left, pressed: true)
        transmitMouseReport(currentAbsoluteReport(buttons: down))
        try await Task.sleep(nanoseconds: 40_000_000)
        let up = setButton(.left, pressed: false)
        transmitMouseReport(currentAbsoluteReport(buttons: up))
    }

    private func performSwipe(_ direction: SwipeDirection) async throws {
        let start: (Double, Double)
        let end: (Double, Double)
        switch direction {
        case .up:
            start = (0.5, 0.85)
            end = (0.5, 0.25)
        case .down:
            start = (0.5, 0.25)
            end = (0.5, 0.85)
        case .left:
            start = (0.8, 0.5)
            end = (0.2, 0.5)
        case .right:
            start = (0.2, 0.5)
            end = (0.8, 0.5)
        }
        movePointerAbsolute(normalizedX: start.0, normalizedY: start.1)
        try await Task.sleep(nanoseconds: 20_000_000)
        let down = setButton(.left, pressed: true)
        transmitMouseReport(currentAbsoluteReport(buttons: down))
        try await Task.sleep(nanoseconds: 30_000_000)
        movePointerAbsolute(normalizedX: end.0, normalizedY: end.1)
        try await Task.sleep(nanoseconds: 20_000_000)
        let up = setButton(.left, pressed: false)
        transmitMouseReport(currentAbsoluteReport(buttons: up))
    }

    private func sendKeyChord(modifiers: UInt8, keyCode: UInt8) async throws {
        transmitKeyboardReport(HIDKeyboardReport(modifiers: modifiers, keyCodes: [keyCode]))
        try await Task.sleep(nanoseconds: 50_000_000)
        transmitKeyboardReport(HIDKeyboardReport(modifiers: 0, keyCodes: []))
    }

    private func sendConsumerPulse(_ usage: ConsumerUsage) async throws {
        transmitConsumerReport(usage.rawValue)
        try await Task.sleep(nanoseconds: 50_000_000)
        transmitConsumerReport(0)
    }

    // MARK: - Button state

    private func setButton(_ button: MouseButton, pressed: Bool) -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        if pressed {
            activeButtons |= button.rawValue
        } else {
            activeButtons &= ~button.rawValue
        }
        return activeButtons
    }

    private func getActiveButtons() -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        return activeButtons
    }

    // MARK: - Transmit

    private func transmitMouseReport(_ report: HIDMouseReport) {
        let data = report.rawData
        lock.lock()
        cachedMouse = data
        lock.unlock()
        // Report protocol absolute payload — do not push to boot mouse (relative boot format).
        notify(data, characteristic: mouseReportChar)
        AppLogger.debug(
            "HID mouse abs: buttons=\(report.buttons) x=\(report.x) y=\(report.y) wheel=\(report.wheel)",
            category: .input
        )
    }

    private func transmitKeyboardReport(_ report: HIDKeyboardReport) {
        let data = report.rawData
        lock.lock()
        cachedKeyboard = data
        lock.unlock()
        notify(data, characteristic: keyboardReportChar)
        notify(data, characteristic: bootKeyboardChar)
        AppLogger.debug("HID keyboard: mods=\(report.modifiers) keys=\(report.keyCodes)", category: .input)
    }

    private func transmitConsumerReport(_ usage: UInt16) {
        var data = Data(count: 2)
        data[0] = UInt8(usage & 0xFF)
        data[1] = UInt8((usage >> 8) & 0xFF)
        lock.lock()
        cachedConsumer = data
        lock.unlock()
        notify(data, characteristic: consumerReportChar)
        AppLogger.debug("HID consumer: 0x\(String(usage, radix: 16))", category: .input)
    }

    private func notify(_ data: Data, characteristic: CBMutableCharacteristic?) {
        guard let characteristic, let peripheralManager else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let centrals = lock.withLock { Array(self.subscribedCentrals.values) }
            guard !centrals.isEmpty else { return }

            if !readyToNotify {
                pendingNotify = (data, characteristic)
                return
            }
            let ok = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: centrals)
            if !ok {
                readyToNotify = false
                pendingNotify = (data, characteristic)
            }
        }
    }

    private func resumeConnectWaiters(error: Error?) {
        lock.lock()
        let waiters = connectWaiters
        connectWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume()
            }
        }
    }

    private func ensureAdvertising() {
        guard let peripheralManager, peripheralManager.state == .poweredOn else { return }
        lock.lock()
        let wants = _wantsAdvertising
        let installed = _servicesInstalled
        lock.unlock()
        guard wants else { return }
        if installed {
            startAdvertisingNow()
        } else {
            installServices()
        }
    }

    private func startAdvertisingNow() {
        guard let peripheralManager else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: AppInfo.displayName,
            CBAdvertisementDataServiceUUIDsKey: [BluetoothHIDProfile.hidService],
        ])
    }

    // MARK: - GATT install

    private func installServices() {
        guard let peripheralManager else { return }
        lock.lock()
        guard !_servicesInstalled else {
            lock.unlock()
            return
        }
        lock.unlock()

        let battery = buildBatteryService()
        peripheralManager.add(battery)
    }

    private func buildBatteryService() -> CBMutableService {
        let service = CBMutableService(type: BluetoothHIDProfile.batteryService, primary: true)
        let level = CBMutableCharacteristic(
            type: BluetoothHIDProfile.batteryLevel,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        batteryLevelChar = level
        service.characteristics = [level]
        return service
    }

    private func buildDeviceInfoService() -> CBMutableService {
        let service = CBMutableService(type: BluetoothHIDProfile.deviceInformationService, primary: true)
        let manufacturer = Data(AppInfo.displayName.utf8)
        let model = Data("\(AppInfo.displayName)-HID".utf8)
        service.characteristics = [
            CBMutableCharacteristic(
                type: BluetoothHIDProfile.manufacturerName,
                properties: [.read],
                value: manufacturer,
                permissions: [.readable]
            ),
            CBMutableCharacteristic(
                type: BluetoothHIDProfile.modelNumber,
                properties: [.read],
                value: model,
                permissions: [.readable]
            ),
            CBMutableCharacteristic(
                type: BluetoothHIDProfile.pnpID,
                properties: [.read],
                value: BluetoothHIDProfile.pnpIDValue,
                permissions: [.readable]
            ),
        ]
        return service
    }

    private func buildHIDService() -> CBMutableService {
        let service = CBMutableService(type: BluetoothHIDProfile.hidService, primary: true)
        // Keep Battery as a separate primary service. Including the wrong CBService
        // (or nesting DIS) breaks iOS HID host binding and leaves pairing on "Connecting…".

        let protocolMode = CBMutableCharacteristic(
            type: BluetoothHIDProfile.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        let hidInfo = CBMutableCharacteristic(
            type: BluetoothHIDProfile.hidInformation,
            properties: [.read],
            value: BluetoothHIDProfile.hidInformationValue,
            permissions: [.readEncryptionRequired]
        )
        let controlPoint = CBMutableCharacteristic(
            type: BluetoothHIDProfile.hidControlPoint,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeEncryptionRequired]
        )

        let bootMouse = CBMutableCharacteristic(
            type: BluetoothHIDProfile.bootMouseInput,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let bootKeyboard = CBMutableCharacteristic(
            type: BluetoothHIDProfile.bootKeyboardInput,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        let bootKeyboardOut = CBMutableCharacteristic(
            type: BluetoothHIDProfile.bootKeyboardOutput,
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )

        let reportMap = CBMutableCharacteristic(
            type: BluetoothHIDProfile.reportMap,
            properties: [.read],
            value: BluetoothHIDProfile.reportMapData,
            permissions: [.readEncryptionRequired]
        )
        reportMap.descriptors = [
            CBMutableDescriptor(
                type: BluetoothHIDProfile.externalReportReference,
                value: BluetoothHIDProfile.externalReportReferenceValue
            ),
        ]

        let mouse = makeInputReport(.mouse)
        let keyboard = makeInputReport(.keyboard)
        let consumer = makeInputReport(.consumer)
        let ledOut = CBMutableCharacteristic(
            type: BluetoothHIDProfile.report,
            properties: [.read, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        ledOut.descriptors = [
            CBMutableDescriptor(
                type: BluetoothHIDProfile.reportReference,
                value: BluetoothHIDProfile.reportReference(.keyboardLEDs, .output)
            ),
        ]

        service.characteristics = [
            protocolMode,
            hidInfo,
            controlPoint,
            bootMouse,
            bootKeyboard,
            bootKeyboardOut,
            reportMap,
            mouse,
            keyboard,
            consumer,
            ledOut,
        ]

        mouseReportChar = mouse
        keyboardReportChar = keyboard
        consumerReportChar = consumer
        bootMouseChar = bootMouse
        bootKeyboardChar = bootKeyboard
        return service
    }

    private func makeInputReport(_ id: BluetoothHIDProfile.ReportID) -> CBMutableCharacteristic {
        let char = CBMutableCharacteristic(
            type: BluetoothHIDProfile.report,
            properties: [.read, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired]
        )
        char.descriptors = [
            CBMutableDescriptor(
                type: BluetoothHIDProfile.reportReference,
                value: BluetoothHIDProfile.reportReference(id, .input)
            ),
        ]
        return char
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothHIDTransport: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        AppLogger.info("Bluetooth HID peripheral state=\(peripheral.state.rawValue)", category: .bluetooth)
        switch peripheral.state {
        case .poweredOn:
            ensureAdvertising()
        case .unauthorized:
            resumeConnectWaiters(error: NSError(
                domain: AppInfo.name,
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Bluetooth permission denied. Enable Bluetooth access in System Settings."]
            ))
        case .poweredOff:
            lock.lock()
            _isAdvertising = false
            lock.unlock()
            AppLogger.warning("Bluetooth powered off — HID control unavailable", category: .bluetooth)
        case .unsupported:
            resumeConnectWaiters(error: NSError(
                domain: AppInfo.name,
                code: 405,
                userInfo: [NSLocalizedDescriptionKey: "Bluetooth LE peripheral role unsupported on this Mac."]
            ))
        default:
            break
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            AppLogger.error("Failed to add HID service \(service.uuid): \(error.localizedDescription)", category: .bluetooth)
            resumeConnectWaiters(error: error)
            return
        }

        switch service.uuid {
        case BluetoothHIDProfile.batteryService:
            peripheral.add(buildDeviceInfoService())
        case BluetoothHIDProfile.deviceInformationService:
            peripheral.add(buildHIDService())
        case BluetoothHIDProfile.hidService:
            lock.lock()
            _servicesInstalled = true
            lock.unlock()
            startAdvertisingNow()
        default:
            break
        }
    }

    public func peripheralManagerDidStartAdvertising(_: CBPeripheralManager, error: Error?) {
        if let error {
            lock.lock()
            _isAdvertising = false
            lock.unlock()
            AppLogger.error("HID advertising failed: \(error.localizedDescription)", category: .bluetooth)
            resumeConnectWaiters(error: error)
            return
        }

        lock.lock()
        _isAdvertising = true
        lock.unlock()
        AppLogger.info("Bluetooth HID advertising as '\(AppInfo.displayName)'", category: .bluetooth)
        resumeConnectWaiters(error: nil)
    }

    public func peripheralManager(
        _: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        lock.lock()
        subscribedCentrals[central.identifier] = central
        _subscribedCentrals.insert(central.identifier)
        let mouse = cachedMouse
        let keyboard = cachedKeyboard
        let consumer = cachedConsumer
        lock.unlock()

        AppLogger.info("iPhone subscribed to HID characteristic \(characteristic.uuid)", category: .bluetooth)

        // Hosts often stall until a baseline report arrives.
        if characteristic === mouseReportChar {
            notify(mouse, characteristic: mouseReportChar)
        } else if characteristic.uuid == BluetoothHIDProfile.bootMouseInput {
            notify(Data([0, 0, 0, 0]), characteristic: bootMouseChar)
        } else if characteristic.uuid == BluetoothHIDProfile.bootKeyboardInput || characteristic === keyboardReportChar {
            notify(keyboard, characteristic: keyboardReportChar)
            notify(keyboard, characteristic: bootKeyboardChar)
        } else if characteristic === consumerReportChar {
            notify(consumer, characteristic: consumerReportChar)
        } else if characteristic.uuid == BluetoothHIDProfile.batteryLevel {
            notify(Data([100]), characteristic: batteryLevelChar)
        }
    }

    public func peripheralManager(
        _: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        lock.lock()
        subscribedCentrals.removeValue(forKey: central.identifier)
        _subscribedCentrals.remove(central.identifier)
        lock.unlock()
        AppLogger.info("iPhone unsubscribed from \(characteristic.uuid)", category: .bluetooth)
    }

    public func peripheralManagerIsReady(toUpdateSubscribers _: CBPeripheralManager) {
        readyToNotify = true
        if let (data, char) = pendingNotify {
            pendingNotify = nil
            notify(data, characteristic: char)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let value: Data? = switch request.characteristic.uuid {
        case BluetoothHIDProfile.batteryLevel:
            Data([100])
        case BluetoothHIDProfile.hidInformation:
            BluetoothHIDProfile.hidInformationValue
        case BluetoothHIDProfile.reportMap:
            BluetoothHIDProfile.reportMapData
        case BluetoothHIDProfile.protocolMode:
            Data([0x01])
        case BluetoothHIDProfile.bootMouseInput:
            Data([0, 0, 0, 0])
        case BluetoothHIDProfile.bootKeyboardInput:
            lock.withLock { cachedKeyboard }
        case BluetoothHIDProfile.report:
            if request.characteristic === mouseReportChar {
                lock.withLock { cachedMouse }
            } else if request.characteristic === keyboardReportChar {
                lock.withLock { cachedKeyboard }
            } else if request.characteristic === consumerReportChar {
                lock.withLock { cachedConsumer }
            } else {
                Data()
            }
        default:
            Data()
        }

        guard let value else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
