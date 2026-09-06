import CoreBluetooth
import Foundation

// Builds and installs Battery / Device Info / HID GATT services expected by iOS AssistiveTouch.
// Order matters: CoreBluetooth adds services asynchronously; chain continues in didAdd.

extension BluetoothHIDTransport {
    // MARK: - GATT install

    /// Starts the Battery → Device Info → HID service add chain when not already installing.
    func installServices() {
        guard let peripheralManager else { return }
        lock.lock()
        guard !servicesInstalled, !servicesInstalling else {
            lock.unlock()
            return
        }
        servicesInstalling = true
        lock.unlock()

        let battery = buildBatteryService()
        peripheralManager.add(battery)
    }

    /// Builds the Battery service and retains the level characteristic for notify/read.
    func buildBatteryService() -> CBMutableService {
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

    /// Builds Device Information with manufacturer/model/PnP values from AppInfo.
    func buildDeviceInfoService() -> CBMutableService {
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

    /// Builds the HID service (report map, input reports, boot chars) and caches report characteristics.
    // swiftlint:disable:next function_body_length
    func buildHIDService() -> CBMutableService {
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

    /// Creates a notify-capable HID Report characteristic with the matching Report Reference descriptor.
    func makeInputReport(_ id: BluetoothHIDProfile.ReportID) -> CBMutableCharacteristic {
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
