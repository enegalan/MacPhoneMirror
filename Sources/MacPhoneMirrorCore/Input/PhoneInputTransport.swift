import Foundation

public enum MouseButton: UInt8, Sendable {
    case left = 1
    case right = 2
    case middle = 4
}

public enum KeyModifier: UInt8, Sendable {
    case none = 0
    case leftControl = 1
    case leftShift = 2
    case leftAlt = 4
    case leftGUI = 8 // Command / Windows
    case rightControl = 16
    case rightShift = 32
    case rightAlt = 64
    case rightGUI = 128
}

public enum PhoneInputEvent: Sendable, Equatable {
    case pointerMove(deltaX: Double, deltaY: Double)
    case pointerTo(normalizedX: Double, normalizedY: Double)
    case pointerDown(button: MouseButton)
    case pointerUp(button: MouseButton)
    case scroll(deltaX: Double, deltaY: Double)
    case keyDown(keyCode: UInt8, modifiers: UInt8)
    case keyUp(keyCode: UInt8)
    case homeButton
    case lockScreen
    case appSwitcher
    case controlCenter
    case notificationCenter
    case volumeUp
    case volumeDown
    case siri
    case swipe(direction: SwipeDirection)
    
    public static func == (lhs: PhoneInputEvent, rhs: PhoneInputEvent) -> Bool {
        switch (lhs, rhs) {
        case (.pointerMove(let x1, let y1), .pointerMove(let x2, let y2)):
            return x1 == x2 && y1 == y2
        case (.pointerTo(let x1, let y1), .pointerTo(let x2, let y2)):
            return x1 == x2 && y1 == y2
        case (.pointerDown(let b1), .pointerDown(let b2)):
            return b1 == b2
        case (.pointerUp(let b1), .pointerUp(let b2)):
            return b1 == b2
        case (.scroll(let x1, let y1), .scroll(let x2, let y2)):
            return x1 == x2 && y1 == y2
        case (.keyDown(let k1, let m1), .keyDown(let k2, let m2)):
            return k1 == k2 && m1 == m2
        case (.keyUp(let k1), .keyUp(let k2)):
            return k1 == k2
        case (.homeButton, .homeButton),
             (.lockScreen, .lockScreen),
             (.appSwitcher, .appSwitcher),
             (.controlCenter, .controlCenter),
             (.notificationCenter, .notificationCenter),
             (.volumeUp, .volumeUp),
             (.volumeDown, .volumeDown),
             (.siri, .siri):
            return true
        case (.swipe(let d1), .swipe(let d2)):
            return d1 == d2
        default:
            return false
        }
    }
}

public enum SwipeDirection: String, Sendable, Codable {
    case up
    case down
    case left
    case right
}

public protocol PhoneInputTransport: AnyObject, Sendable {
    var isConnected: Bool { get }
    var transportName: String { get }
    
    func connect() async throws
    func disconnect()
    func send(_ event: PhoneInputEvent) async throws
}
