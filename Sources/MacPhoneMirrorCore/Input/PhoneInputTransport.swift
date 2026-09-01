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
        case let (.pointerMove(x1, y1), .pointerMove(x2, y2)):
            x1 == x2 && y1 == y2
        case let (.pointerTo(x1, y1), .pointerTo(x2, y2)):
            x1 == x2 && y1 == y2
        case let (.pointerDown(b1), .pointerDown(b2)):
            b1 == b2
        case let (.pointerUp(b1), .pointerUp(b2)):
            b1 == b2
        case let (.scroll(x1, y1), .scroll(x2, y2)):
            x1 == x2 && y1 == y2
        case let (.keyDown(k1, m1), .keyDown(k2, m2)):
            k1 == k2 && m1 == m2
        case let (.keyUp(k1), .keyUp(k2)):
            k1 == k2
        case (.homeButton, .homeButton),
             (.lockScreen, .lockScreen),
             (.appSwitcher, .appSwitcher),
             (.controlCenter, .controlCenter),
             (.notificationCenter, .notificationCenter),
             (.volumeUp, .volumeUp),
             (.volumeDown, .volumeDown),
             (.siri, .siri):
            true
        case let (.swipe(d1), .swipe(d2)):
            d1 == d2
        default:
            false
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
