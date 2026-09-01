import Foundation

public enum Feature: String, CaseIterable, Identifiable, Codable, Sendable {
    case screenMirroring = "Screen Mirroring"
    case basicFrame = "Basic iPhone Frame"
    case advancedControl = "Bluetooth HID Remote Control"
    case highQuality = "Ultra HD / 60 FPS Mode"
    case lowLatencyMode = "Ultra Low Latency Pipeline"
    case multiDevice = "Multiple Device Profiles"
    case recording = "Screen Recording & Capture"
    case customFrames = "Titanium & Custom Frame Finishes"
    case keyboardShortcuts = "Full Keyboard Navigation"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .screenMirroring:
            return "Mirror your iPhone screen in real-time on your Mac"
        case .basicFrame:
            return "Display mirrored screen in a standard frame"
        case .advancedControl:
            return "Control your iPhone with Mac mouse, trackpad, and keyboard"
        case .highQuality:
            return "Crystal clear 60 FPS hardware accelerated stream"
        case .lowLatencyMode:
            return "Sub-15ms video decode and render pipeline"
        case .multiDevice:
            return "Save and switch between multiple iPhones quickly"
        case .recording:
            return "Capture high-resolution video recordings and snapshots"
        case .customFrames:
            return "Natural Titanium, Black, Desert, and custom finishes"
        case .keyboardShortcuts:
            return "Send iOS shortcuts, Spotlight search, App Switcher, and Home keys"
        }
    }
}
