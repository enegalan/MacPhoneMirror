import Foundation

public struct AssistiveTouchAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let event: PhoneInputEvent
    public let shortcutHint: String
    public let description: String

    public init(id: String, title: String, systemImage: String, event: PhoneInputEvent, shortcutHint: String, description: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.event = event
        self.shortcutHint = shortcutHint
        self.description = description
    }
}

public struct AssistiveTouchProfile: Sendable {
    public static let standardActions: [AssistiveTouchAction] = [
        AssistiveTouchAction(
            id: "home",
            title: "Home",
            systemImage: "house.fill",
            event: .homeButton,
            shortcutHint: "⌘⇧H",
            description: "Return to iOS Home Screen"
        ),
        AssistiveTouchAction(
            id: "appSwitcher",
            title: "App Switcher",
            systemImage: "square.2.layers.3d",
            event: .appSwitcher,
            shortcutHint: "⌘⇧Tab",
            description: "Show running apps in multitasking view"
        ),
        AssistiveTouchAction(
            id: "controlCenter",
            title: "Control Center",
            systemImage: "switch.2",
            event: .controlCenter,
            shortcutHint: "⌘⇧C",
            description: "Open iOS Control Center toggles"
        ),
        AssistiveTouchAction(
            id: "notificationCenter",
            title: "Notifications",
            systemImage: "bell.fill",
            event: .notificationCenter,
            shortcutHint: "⌘⇧N",
            description: "Pull down iOS Notification Center"
        ),
        AssistiveTouchAction(
            id: "lockScreen",
            title: "Lock Screen",
            systemImage: "lock.fill",
            event: .lockScreen,
            shortcutHint: "⌘⇧L",
            description: "Lock or wake the iPhone"
        ),
        AssistiveTouchAction(
            id: "siri",
            title: "Siri",
            systemImage: "waveform.badge.magnifyingglass",
            event: .siri,
            shortcutHint: "⌘⇧S",
            description: "Activate Siri voice assistant"
        ),
        AssistiveTouchAction(
            id: "volumeUp",
            title: "Volume Up",
            systemImage: "speaker.wave.3.fill",
            event: .volumeUp,
            shortcutHint: "⌘↑",
            description: "Increase iOS audio volume"
        ),
        AssistiveTouchAction(
            id: "volumeDown",
            title: "Volume Down",
            systemImage: "speaker.wave.1.fill",
            event: .volumeDown,
            shortcutHint: "⌘↓",
            description: "Decrease iOS audio volume"
        ),
    ]
}
