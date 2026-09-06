import CoreBluetooth
import Foundation

// CBPeripheralManagerDelegate callbacks for power state, service add, advertising, and CCCD subscribe.
// Resumes connect() waiters on success/failure.

extension BluetoothHIDTransport: CBPeripheralManagerDelegate {
    /// On poweredOn, starts advertising/service install; on unauthorized/unsupported, fails connect waiters.
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        AppLogger.info("Bluetooth HID peripheral state=\(peripheral.state.rawValue)", category: .bluetooth)
        switch peripheral.state {
        case .poweredOn:
            ensureAdvertising()
        case .unauthorized:
            resumeConnectWaiters(error: NSError(
                domain: AppInfo.name,
                code: 403,
                userInfo: [
                    NSLocalizedDescriptionKey: "Bluetooth permission denied. "
                        + "Enable Bluetooth access in System Settings.",
                ]
            ))
        case .poweredOff:
            lock.lock()
            isAdvertisingActive = false
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

    /// Chains Battery → Device Info → HID adds; on HID success, starts advertising.
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            lock.lock()
            servicesInstalling = false
            lock.unlock()
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
            servicesInstalled = true
            servicesInstalling = false
            lock.unlock()
            startAdvertisingNow()
        default:
            break
        }
    }

    /// Marks advertising active and resumes connect waiters; cancels if `wantsAdvertising` was cleared.
    public func peripheralManagerDidStartAdvertising(_: CBPeripheralManager, error: Error?) {
        if let error {
            lock.lock()
            isAdvertisingActive = false
            lock.unlock()
            AppLogger.error("HID advertising failed: \(error.localizedDescription)", category: .bluetooth)
            resumeConnectWaiters(error: error)
            return
        }

        lock.lock()
        let wantsAdvertising = wantsAdvertising
        if wantsAdvertising {
            isAdvertisingActive = true
        } else {
            isAdvertisingActive = false
        }
        lock.unlock()

        guard wantsAdvertising else {
            peripheralManager?.stopAdvertising()
            resumeConnectWaiters(error: NSError(
                domain: AppInfo.name,
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Bluetooth HID advertising was cancelled before it started."]
            ))
            return
        }

        AppLogger.info("Bluetooth HID advertising as '\(AppInfo.displayName)'", category: .bluetooth)
        resumeConnectWaiters(error: nil)
    }

    /// Tracks the iPhone central and pushes a baseline report so AssistiveTouch finishes binding.
    public func peripheralManager(
        _: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        lock.lock()
        subscribedCentrals[central.identifier] = central
        subscribedCentralIDs.insert(central.identifier)
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
        } else if characteristic.uuid == BluetoothHIDProfile.bootKeyboardInput
            || characteristic === keyboardReportChar
        {
            notify(keyboard, characteristic: keyboardReportChar)
            notify(keyboard, characteristic: bootKeyboardChar)
        } else if characteristic === consumerReportChar {
            notify(consumer, characteristic: consumerReportChar)
        } else if characteristic.uuid == BluetoothHIDProfile.batteryLevel {
            notify(Data([100]), characteristic: batteryLevelChar)
        }
    }

    /// Drops the central from the subscriber set so further notifies skip it.
    public func peripheralManager(
        _: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        lock.lock()
        subscribedCentrals.removeValue(forKey: central.identifier)
        subscribedCentralIDs.remove(central.identifier)
        lock.unlock()
        AppLogger.info("iPhone unsubscribed from \(characteristic.uuid)", category: .bluetooth)
    }

    /// Re-enables notify flow and drains any queued HID report updates.
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        readyToNotify = true
        drainPendingNotifications(using: peripheral)
    }

    /// Serves static HID/Battery values and cached report payloads for ATT reads.
    // swiftlint:disable:next cyclomatic_complexity
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

    /// Acknowledges LED/control-point writes so iOS keeps the HID session alive.
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }
}

private extension NSLock {
    /// Runs `body` while holding the lock; always unlocks on exit.
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
