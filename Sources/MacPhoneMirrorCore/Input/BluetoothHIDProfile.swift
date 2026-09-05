import CoreBluetooth
import Foundation

/// HID-over-GATT UUIDs and report map (Bluetooth SIG / USB HID).
/// Full 128-bit forms required: CoreBluetooth rejects short reserved UUIDs on peripheral.
enum BluetoothHIDProfile {
    // CBUUID is not Sendable; values are immutable once created.
    nonisolated(unsafe) static let batteryService = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let deviceInformationService = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidService = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")

    nonisolated(unsafe) static let reportReference = CBUUID(string: "00002908-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let externalReportReference = CBUUID(string: "00002907-0000-1000-8000-00805F9B34FB")

    nonisolated(unsafe) static let batteryLevel = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidInformation = CBUUID(string: "00002A4A-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let reportMap = CBUUID(string: "00002A4B-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let hidControlPoint = CBUUID(string: "00002A4C-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let report = CBUUID(string: "00002A4D-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let protocolMode = CBUUID(string: "00002A4E-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootKeyboardInput = CBUUID(string: "00002A22-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootKeyboardOutput = CBUUID(string: "00002A32-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let bootMouseInput = CBUUID(string: "00002A33-0000-1000-8000-00805F9B34FB")

    nonisolated(unsafe) static let manufacturerName = CBUUID(string: "00002A29-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let modelNumber = CBUUID(string: "00002A24-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) static let pnpID = CBUUID(string: "00002A50-0000-1000-8000-00805F9B34FB")

    /// bcdHID 1.11, country 0, flags: RemoteWake | NormallyConnectable
    static let hidInformationValue = Data([0x11, 0x01, 0x00, 0x03])
    static let externalReportReferenceValue = Data([0x19, 0x2A])
    static let pnpIDValue = Data([0x01, 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x01])

    enum ReportID: UInt8 {
        case mouse = 1
        case keyboard = 2
        case keyboardLEDs = 3
        case consumer = 4
    }

    enum ReportType: UInt8 {
        case input = 1
        case output = 2
    }

    static func reportReference(_ id: ReportID, _ type: ReportType) -> Data {
        Data([id.rawValue, type.rawValue])
    }

    /// Absolute mouse (AssistiveTouch) + keyboard + consumer control.
    /// Absolute X/Y (0…32767) so click-to-position does not depend on relative tracking speed.
    static let reportMapData = Data([
        // Absolute mouse — Report ID 1
        0x05, 0x01,
        0x09, 0x02,
        0xA1, 0x01,
        0x85, 0x01,
        0x09, 0x01,
        0xA1, 0x00,
        0x05, 0x09,
        0x19, 0x01,
        0x29, 0x03,
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x03,
        0x81, 0x02,
        0x95, 0x05,
        0x81, 0x03,
        0x05, 0x01,
        0x09, 0x30,
        0x09, 0x31,
        0x15, 0x00,
        0x26, 0xFF, 0x7F,
        0x75, 0x10,
        0x95, 0x02,
        0x81, 0x02,
        0x09, 0x38,
        0x15, 0x81,
        0x25, 0x7F,
        0x75, 0x08,
        0x95, 0x01,
        0x81, 0x06,
        0xC0,
        0xC0,

        // Keyboard — Report ID 2 / LED output Report ID 3
        0x05, 0x01,
        0x09, 0x06,
        0xA1, 0x01,
        0x85, 0x02,
        0x05, 0x07,
        0x19, 0xE0,
        0x29, 0xE7,
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x08,
        0x81, 0x02,
        0x95, 0x01,
        0x75, 0x08,
        0x81, 0x01,
        0x19, 0x00,
        0x29, 0xDD,
        0x15, 0x00,
        0x25, 0xDD,
        0x75, 0x08,
        0x95, 0x06,
        0x81, 0x00,
        0x85, 0x03,
        0x05, 0x08,
        0x19, 0x01,
        0x29, 0x05,
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x05,
        0x91, 0x02,
        0x95, 0x03,
        0x91, 0x03,
        0xC0,

        // Consumer Control — Report ID 4
        0x05, 0x0C,
        0x09, 0x01,
        0xA1, 0x01,
        0x85, 0x04,
        0x15, 0x00,
        0x26, 0xFF, 0x03,
        0x19, 0x00,
        0x2A, 0xFF, 0x03,
        0x75, 0x10,
        0x95, 0x01,
        0x81, 0x00,
        0xC0,
    ])
}

enum ConsumerUsage: UInt16 {
    case power = 0x0030
    case menu = 0x0040
    case voiceCommand = 0x00CF
    case volumeIncrement = 0x00E9
    case volumeDecrement = 0x00EA
    case acHome = 0x0223
    case acSearch = 0x0221
}

/// Absolute mouse report: buttons + X/Y (0…32767 LE) + wheel.
public struct HIDMouseReport: Sendable {
    public static let axisMax: UInt16 = 32767

    public var buttons: UInt8 = 0
    public var x: UInt16 = 0
    public var y: UInt16 = 0
    public var wheel: Int8 = 0

    public init(buttons: UInt8 = 0, x: UInt16 = 0, y: UInt16 = 0, wheel: Int8 = 0) {
        self.buttons = buttons
        self.x = x
        self.y = y
        self.wheel = wheel
    }

    public static func fromNormalized(buttons: UInt8, normalizedX: Double, normalizedY: Double, wheel: Int8 = 0) -> HIDMouseReport {
        let nx = min(max(normalizedX, 0), 1)
        let ny = min(max(normalizedY, 0), 1)
        return HIDMouseReport(
            buttons: buttons,
            x: UInt16((nx * Double(axisMax)).rounded()),
            y: UInt16((ny * Double(axisMax)).rounded()),
            wheel: wheel
        )
    }

    public var rawData: Data {
        Data([
            buttons,
            UInt8(x & 0xFF),
            UInt8((x >> 8) & 0xFF),
            UInt8(y & 0xFF),
            UInt8((y >> 8) & 0xFF),
            UInt8(bitPattern: wheel),
        ])
    }
}

public struct HIDKeyboardReport: Sendable {
    public var modifiers: UInt8 = 0
    public var reserved: UInt8 = 0
    public var keyCodes: [UInt8] = [0, 0, 0, 0, 0, 0]

    public init(modifiers: UInt8 = 0, keyCodes: [UInt8] = [0, 0, 0, 0, 0, 0]) {
        self.modifiers = modifiers
        var padded = keyCodes
        while padded.count < 6 {
            padded.append(0)
        }
        self.keyCodes = Array(padded.prefix(6))
    }

    public var rawData: Data {
        var data = Data([modifiers, reserved])
        data.append(contentsOf: keyCodes)
        return data
    }
}
