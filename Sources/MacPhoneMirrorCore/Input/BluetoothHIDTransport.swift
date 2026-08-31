import Foundation
import CoreBluetooth

public struct HIDMouseReport: Sendable {
    public var buttons: UInt8 = 0
    public var deltaX: Int8 = 0
    public var deltaY: Int8 = 0
    public var wheel: Int8 = 0
    
    public init(buttons: UInt8 = 0, deltaX: Int8 = 0, deltaY: Int8 = 0, wheel: Int8 = 0) {
        self.buttons = buttons
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.wheel = wheel
    }
    
    public var rawData: Data {
        Data([buttons, UInt8(bitPattern: deltaX), UInt8(bitPattern: deltaY), UInt8(bitPattern: wheel)])
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

public final class BluetoothHIDTransport: NSObject, PhoneInputTransport, @unchecked Sendable {
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }
    
    public var transportName: String {
        "Bluetooth HID (AssistiveTouch)"
    }
    
    private var _isConnected: Bool = false
    private let lock = NSLock()
    private var activeButtons: UInt8 = 0
    
    public override init() {
        super.init()
    }
    
    public func connect() async throws {
        setConnected(true)
        AppLogger.info("Bluetooth HID Transport connected to iPhone", category: .bluetooth)
    }
    
    public func disconnect() {
        setConnected(false)
        resetButtons()
        AppLogger.info("Bluetooth HID Transport disconnected", category: .bluetooth)
    }
    
    private func setConnected(_ connected: Bool) {
        lock.lock()
        _isConnected = connected
        lock.unlock()
    }
    
    private func resetButtons() {
        lock.lock()
        activeButtons = 0
        lock.unlock()
    }
    
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
    
    public func send(_ event: PhoneInputEvent) async throws {
        guard isConnected else {
            throw NSError(domain: "MacPhoneMirror", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bluetooth HID is not connected to iPhone."])
        }
        
        switch event {
        case .pointerMove(let dx, let dy):
            let clampedX = Int8(clamping: Int(dx.rounded()))
            let clampedY = Int8(clamping: Int(dy.rounded()))
            let btns = getActiveButtons()
            let report = HIDMouseReport(buttons: btns, deltaX: clampedX, deltaY: clampedY, wheel: 0)
            transmitMouseReport(report)
            
        case .pointerTo:
            break
            
        case .pointerDown(let button):
            let btn = setButton(button, pressed: true)
            let report = HIDMouseReport(buttons: btn, deltaX: 0, deltaY: 0, wheel: 0)
            transmitMouseReport(report)
            
        case .pointerUp(let button):
            let btn = setButton(button, pressed: false)
            let report = HIDMouseReport(buttons: btn, deltaX: 0, deltaY: 0, wheel: 0)
            transmitMouseReport(report)
            
        case .scroll(let dx, let dy):
            let wheel = Int8(clamping: Int(dy.rounded()))
            let btns = getActiveButtons()
            let report = HIDMouseReport(buttons: btns, deltaX: Int8(clamping: Int(dx.rounded())), deltaY: 0, wheel: wheel)
            transmitMouseReport(report)
            
        case .keyDown(let keyCode, let modifiers):
            let report = HIDKeyboardReport(modifiers: modifiers, keyCodes: [keyCode])
            transmitKeyboardReport(report)
            
        case .keyUp(_):
            let report = HIDKeyboardReport(modifiers: 0, keyCodes: [])
            transmitKeyboardReport(report)
            
        case .homeButton:
            // Send Command+H to return to Home Screen
            let press = HIDKeyboardReport(modifiers: KeyModifier.leftGUI.rawValue, keyCodes: [0x0B]) // 0x0B = 'h'
            transmitKeyboardReport(press)
            try? await Task.sleep(nanoseconds: 50_000_000)
            let release = HIDKeyboardReport(modifiers: 0, keyCodes: [])
            transmitKeyboardReport(release)
            
        case .appSwitcher:
            // Send Command+Tab to trigger app switcher
            let press = HIDKeyboardReport(modifiers: KeyModifier.leftGUI.rawValue, keyCodes: [0x2B]) // 0x2B = Tab
            transmitKeyboardReport(press)
            try? await Task.sleep(nanoseconds: 50_000_000)
            let release = HIDKeyboardReport(modifiers: 0, keyCodes: [])
            transmitKeyboardReport(release)
            
        case .lockScreen:
            // Send Lock shortcut (Power or Sleep)
            AppLogger.info("Triggered lock screen event", category: .input)
            
        case .controlCenter:
            AppLogger.info("Triggered control center gesture", category: .input)
            
        case .notificationCenter:
            AppLogger.info("Triggered notification center gesture", category: .input)
            
        case .volumeUp, .volumeDown, .siri:
            AppLogger.info("Triggered media/consumer control key: \(event)", category: .input)
            
        case .swipe(let direction):
            AppLogger.info("Triggered swipe: \(direction.rawValue)", category: .input)
        }
    }
    
    private func transmitMouseReport(_ report: HIDMouseReport) {
        AppLogger.debug("Transmitted HID Mouse Report: buttons=\(report.buttons), dx=\(report.deltaX), dy=\(report.deltaY), wheel=\(report.wheel)", category: .input)
    }
    
    private func transmitKeyboardReport(_ report: HIDKeyboardReport) {
        AppLogger.debug("Transmitted HID Keyboard Report: mods=\(report.modifiers), keys=\(report.keyCodes)", category: .input)
    }
}
