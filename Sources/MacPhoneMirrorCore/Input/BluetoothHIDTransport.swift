import CoreBluetooth
import Foundation

/// Bluetooth HID peripheral that the iPhone pairs as an AssistiveTouch pointer.
/// AirPlay carries video only; pointer/keyboard control needs this separate HID channel.
// swiftlint:disable:next type_body_length
public final class BluetoothHIDTransport: NSObject, PhoneInputTransport, @unchecked Sendable {
    public static let shared = BluetoothHIDTransport()

    /// True when we are advertising or an iPhone has subscribed to HID notifies.
    /// Does not guarantee AssistiveTouch is enabled on the phone — only that the Mac side is usable.
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAdvertisingActive || !subscribedCentralIDs.isEmpty
    }

    public var transportName: String {
        "Bluetooth HID (AssistiveTouch)"
    }

    public var hasSubscribers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !subscribedCentralIDs.isEmpty
    }

    var peripheralManager: CBPeripheralManager?
    var mouseReportChar: CBMutableCharacteristic?
    var keyboardReportChar: CBMutableCharacteristic?
    var consumerReportChar: CBMutableCharacteristic?
    var bootMouseChar: CBMutableCharacteristic?
    var bootKeyboardChar: CBMutableCharacteristic?
    var batteryLevelChar: CBMutableCharacteristic?

    var isAdvertisingActive = false
    var wantsAdvertising = false
    var servicesInstalled = false
    var servicesInstalling = false
    var activeButtons: UInt8 = 0
    var readyToNotify = true
    var pendingNotifyQueues: [ObjectIdentifier: [Data]] = [:]
    var pendingNotifyCharacteristics: [ObjectIdentifier: CBMutableCharacteristic] = [:]
    var subscribedCentrals: [UUID: CBCentral] = [:]
    var subscribedCharacteristicIDs: [UUID: Set<CBUUID>] = [:]
    var subscribedCentralIDs: Set<UUID> = []
    var cachedMouse = Data([0, 0, 0, 0, 0, 0])
    var cachedKeyboard = Data([0, 0, 0, 0, 0, 0, 0, 0])
    var cachedConsumer = Data([0, 0])
    var lastAbsX: UInt16 = 0
    var lastAbsY: UInt16 = 0
    let baseRelativeMoveScale: Double = 48

    var relativeMoveScale: Double {
        baseRelativeMoveScale * AppPreferences.mouseSensitivity
    }

    let lock = NSLock()
    var connectWaiters: [CheckedContinuation<Void, Error>] = []
    let queue = DispatchQueue(label: "com.macphonemirror.hid", qos: .userInitiated)

    /// Creates the shared-capable HID transport; advertising starts only via `connect()`.
    override public init() {
        super.init()
    }

    /// Starts HID advertising (or reuses an active one), racing against a connect timeout.
    public func connect() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.connectOnce() }
            group.addTask {
                try await Task.sleep(nanoseconds: HIDTiming.connectWaitNs)
                let timeout = NSError(
                    domain: AppInfo.name,
                    code: 408,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Bluetooth HID advertising timed out. "
                            + "Grant Bluetooth permission and ensure Bluetooth is On.",
                    ]
                )
                // Resume waiters before this task throws so connectOnce cannot hang
                // under task-group cancellation waiting on an unresumed continuation.
                self.resumeConnectWaiters(error: timeout)
                throw timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Creates the peripheral manager if needed and waits until advertising succeeds or fails.
    func connectOnce() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            wantsAdvertising = true
            if isAdvertisingActive {
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

    /// Intentional no-op so closing a mirror session does not drop shared AssistiveTouch pairing.
    public func disconnect() {
        // Intentional no-op: HID is process-wide and shared across mirror sessions.
        // Stopping advertising on every session close would drop AssistiveTouch pairing mid-use.
        // Call stopAdvertising() only when the user disables the AirPlay service.
    }

    /// Stops BLE advertising when the user disables the AirPlay service.
    public func stopAdvertising() {
        lock.lock()
        wantsAdvertising = false
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            peripheralManager?.stopAdvertising()
            lock.lock()
            isAdvertisingActive = false
            lock.unlock()
            AppLogger.info("Bluetooth HID advertising stopped", category: .bluetooth)
        }
    }

    /// Maps a `PhoneInputEvent` to HID reports; drops events until an iPhone has subscribed.
    // swiftlint:disable:next cyclomatic_complexity
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func send(_ event: PhoneInputEvent) async throws {
        guard isConnected else {
            throw NSError(
                domain: AppInfo.name,
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey: "Bluetooth HID is not advertising. "
                        + "Enable Bluetooth and pair via AssistiveTouch.",
                ]
            )
        }

        if !hasSubscribers {
            AppLogger.debug(
                "HID event dropped — no iPhone subscribed yet. Pair in AssistiveTouch → Devices.",
                category: .input
            )
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

        case .scroll:
            // Scroll is done by click-drag in the mirror viewport; ignore wheel events.
            break

        case let .keyDown(keyCode, modifiers):
            transmitKeyboardReport(HIDKeyboardReport(modifiers: modifiers, keyCodes: [keyCode]))

        case .keyUp:
            transmitKeyboardReport(HIDKeyboardReport(modifiers: 0, keyCodes: []))

        case .homeButton:
            // Quick swipe up from home indicator → Home Screen.
            try await performDrag(
                from: (0.5, 0.98),
                to: (0.5, 0.55),
                steps: 4,
                stepDelayNs: 18_000_000,
                holdAtEndNs: 0
            )

        case .appSwitcher:
            // Swipe up and pause → App Switcher.
            try await performDrag(
                from: (0.5, 0.98),
                to: (0.5, 0.42),
                steps: 8,
                stepDelayNs: 30_000_000,
                holdAtEndNs: 350_000_000
            )

        case .lockScreen:
            try await sendConsumerPulse(.power)

        case .controlCenter:
            try await performDrag(
                from: (0.92, 0.005),
                to: (0.92, 0.45),
                steps: 8,
                stepDelayNs: 28_000_000,
                holdAtEndNs: 0
            )

        case .notificationCenter:
            try await performDrag(
                from: (0.5, 0.005),
                to: (0.5, 0.48),
                steps: 8,
                stepDelayNs: 28_000_000,
                holdAtEndNs: 0
            )

        case .volumeUp:
            try await sendConsumerPulse(.volumeIncrement)

        case .volumeDown:
            try await sendConsumerPulse(.volumeDecrement)

        case .siri:
            // Side-button long-press approximation via consumer Voice Command.
            try await sendConsumerPulse(.voiceCommand)

        case let .swipe(direction):
            try await performSwipe(direction)
        }
    }

    // MARK: - Button state

    /// Updates the pressed-button bitmask and returns the new combined value.
    func setButton(_ button: MouseButton, pressed: Bool) -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        if pressed {
            activeButtons |= button.rawValue
        } else {
            activeButtons &= ~button.rawValue
        }
        return activeButtons
    }

    /// Snapshot of currently pressed mouse buttons under the transport lock.
    func getActiveButtons() -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        return activeButtons
    }

    // MARK: - Transmit

    /// Caches and notifies the absolute mouse report (report protocol only, not boot mouse).
    func transmitMouseReport(_ report: HIDMouseReport) {
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

    /// Caches and notifies keyboard report on both report and boot keyboard characteristics.
    func transmitKeyboardReport(_ report: HIDKeyboardReport) {
        let data = report.rawData
        lock.lock()
        cachedKeyboard = data
        lock.unlock()
        notify(data, characteristic: keyboardReportChar)
        notify(data, characteristic: bootKeyboardChar)
        AppLogger.debug("HID keyboard: mods=\(report.modifiers) keys=\(report.keyCodes)", category: .input)
    }

    /// Encodes a 16-bit consumer usage and notifies subscribed centrals.
    func transmitConsumerReport(_ usage: UInt16) {
        var data = Data(count: 2)
        data[0] = UInt8(usage & 0xFF)
        data[1] = UInt8((usage >> 8) & 0xFF)
        lock.lock()
        cachedConsumer = data
        lock.unlock()
        notify(data, characteristic: consumerReportChar)
        AppLogger.debug("HID consumer: 0x\(String(usage, radix: 16))", category: .input)
    }

    /// Pushes `data` via CoreBluetooth’s per-characteristic subscriber set, or queues when not ready.
    func notify(_ data: Data, characteristic: CBMutableCharacteristic?) {
        guard let characteristic, let peripheralManager else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let hasSubscribers = lock.withLock { !self.subscribedCentralIDs.isEmpty }
            guard hasSubscribers else { return }

            if !readyToNotify {
                enqueuePendingNotify(data, characteristic: characteristic)
                return
            }
            // nil → CoreBluetooth notifies only centrals subscribed to this characteristic.
            let ok = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
            if !ok {
                readyToNotify = false
                enqueuePendingNotify(data, characteristic: characteristic)
            }
        }
    }

    /// Appends a failed notify payload to the per-characteristic pending queue.
    func enqueuePendingNotify(_ data: Data, characteristic: CBMutableCharacteristic) {
        let id = ObjectIdentifier(characteristic)
        pendingNotifyCharacteristics[id] = characteristic
        var queue = pendingNotifyQueues[id] ?? []
        queue.append(data)
        pendingNotifyQueues[id] = queue
    }

    /// Flushes queued notify payloads until the peripheral back-pressures again.
    func drainPendingNotifications(using peripheralManager: CBPeripheralManager) {
        let hasSubscribers = lock.withLock { !subscribedCentralIDs.isEmpty }
        guard hasSubscribers else {
            pendingNotifyQueues.removeAll()
            pendingNotifyCharacteristics.removeAll()
            return
        }

        while readyToNotify, !pendingNotifyQueues.isEmpty {
            var sentAny = false
            for id in Array(pendingNotifyQueues.keys) {
                guard var queue = pendingNotifyQueues[id], !queue.isEmpty,
                      let characteristic = pendingNotifyCharacteristics[id]
                else {
                    pendingNotifyQueues.removeValue(forKey: id)
                    pendingNotifyCharacteristics.removeValue(forKey: id)
                    continue
                }
                let data = queue.removeFirst()
                let ok = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
                if ok {
                    sentAny = true
                    if queue.isEmpty {
                        pendingNotifyQueues.removeValue(forKey: id)
                        pendingNotifyCharacteristics.removeValue(forKey: id)
                    } else {
                        pendingNotifyQueues[id] = queue
                    }
                } else {
                    queue.insert(data, at: 0)
                    pendingNotifyQueues[id] = queue
                    readyToNotify = false
                    return
                }
            }
            if !sentAny {
                break
            }
        }
    }

    /// Completes all pending `connect()` continuations with success or `error`.
    func resumeConnectWaiters(error: Error?) {
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

    /// When powered on and advertising is wanted, installs GATT or starts advertising.
    func ensureAdvertising() {
        guard let peripheralManager, peripheralManager.state == .poweredOn else { return }
        lock.lock()
        let wants = wantsAdvertising
        let installed = servicesInstalled
        lock.unlock()
        guard wants else { return }
        if installed {
            startAdvertisingNow()
        } else {
            installServices()
        }
    }

    /// Begins BLE advertising with the app display name and HID service UUID.
    func startAdvertisingNow() {
        guard let peripheralManager else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: AppInfo.displayName,
            CBAdvertisementDataServiceUUIDsKey: [BluetoothHIDProfile.hidService],
        ])
    }
}
