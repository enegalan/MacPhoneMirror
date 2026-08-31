import Foundation

public enum Feature: String, CaseIterable, Identifiable, Codable, Sendable {
    case screenMirroring = "Screen Mirroring (Standard)"
    case basicFrame = "Basic iPhone Frame"
    case advancedControl = "Bluetooth HID Remote Control"
    case highQuality = "Ultra HD / 60 FPS Mode"
    case lowLatencyMode = "Ultra Low Latency Pipeline"
    case multiDevice = "Multiple Device Profiles"
    case recording = "Screen Recording & Pro Capture"
    case customFrames = "Titanium & Custom Frame Finishes"
    case keyboardShortcuts = "Full Keyboard Navigation"
    
    public var id: String { rawValue }
    
    public var isProOnly: Bool {
        switch self {
        case .screenMirroring, .basicFrame:
            return false
        case .advancedControl, .highQuality, .lowLatencyMode, .multiDevice, .recording, .customFrames, .keyboardShortcuts:
            return true
        }
    }
    
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
            return "Unlock Natural Titanium, Black, Desert, and custom finishes"
        case .keyboardShortcuts:
            return "Send iOS shortcuts, Spotlight search, App Switcher, and Home keys"
        }
    }
}

public protocol EntitlementProvider: Sendable {
    var isProUser: Bool { get }
    func isEnabled(_ feature: Feature) -> Bool
    func unlockPro(licenseKey: String) async -> Bool
    func restorePurchases() async -> Bool
}

public final class LocalEntitlementProvider: EntitlementProvider, @unchecked Sendable {
    public static let shared = LocalEntitlementProvider()
    
    private let userDefaults = UserDefaults.standard
    private let proKey = "com.macphonemirror.isProUser"
    private let lock = NSLock()
    
    private var _isProUser: Bool = false
    
    public var isProUser: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isProUser
    }
    
    public init() {
        self._isProUser = userDefaults.bool(forKey: proKey)
    }
    
    public func isEnabled(_ feature: Feature) -> Bool {
        if !feature.isProOnly {
            return true
        }
        return isProUser
    }
    
    public func unlockPro(licenseKey: String) async -> Bool {
        // Validate license key (mock implementation accepting valid demo format or non-empty string)
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            setProStatusDirectly(true)
            AppLogger.info("MacPhoneMirror Pro unlocked successfully", category: .security)
            return true
        }
        return false
    }
    
    public func setProStatusDirectly(_ enabled: Bool) {
        lock.lock()
        _isProUser = enabled
        userDefaults.set(enabled, forKey: proKey)
        lock.unlock()
    }
    
    public func restorePurchases() async -> Bool {
        return isProUser
    }
}
