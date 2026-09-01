import AppKit
import AVFoundation
import CoreBluetooth
import Foundation
import Network

public enum SystemPermission: String, CaseIterable, Identifiable, Sendable {
    case localNetwork = "Local Network"
    case bluetooth = "Bluetooth"
    case cameraAndCapture = "Screen / Device Capture"
    case accessibility = "Accessibility (Input Emulation)"

    public var id: String {
        rawValue
    }

    public var reasonDescription: String {
        switch self {
        case .localNetwork:
            "Required to discover iPhones advertising AirPlay / Bonjour services on your local Wi-Fi network."
        case .bluetooth:
            "Required to pair MacPhoneMirror as a Bluetooth HID device for mouse and keyboard control."
        case .cameraAndCapture:
            "Required by macOS AVFoundation to access tethered iPhone video streams via USB."
        case .accessibility:
            "Optional helper for global hotkeys and mouse coordinate monitoring."
        }
    }
}

public final class PermissionManager: NSObject, @unchecked Sendable {
    public static let shared = PermissionManager()

    private var _localNetworkAuthorized = false
    private let lock = NSLock()
    private var localNetworkBrowser: NWBrowser?

    override private init() {
        super.init()
    }

    public func checkPermissionStatus(_ permission: SystemPermission) -> Bool {
        switch permission {
        case .cameraAndCapture:
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            return status == .authorized
        case .accessibility:
            return AXIsProcessTrusted()
        case .bluetooth:
            return true
        case .localNetwork:
            lock.lock()
            defer { lock.unlock() }
            return _localNetworkAuthorized
        }
    }

    public func requestLocalNetworkPermission() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_airplay._tcp", domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.lock.lock()
                self?._localNetworkAuthorized = true
                self?.lock.unlock()
            }
        }

        browser.start(queue: .main)
        localNetworkBrowser = browser

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.localNetworkBrowser?.cancel()
            self?.localNetworkBrowser = nil
        }
    }

    public func startAirPlayAdvertising() async {
        requestLocalNetworkPermission()
        do {
            try await NetworkStreamReceiver.shared.start()
        } catch {
            AppLogger.error("Failed to start AirPlay advertising: \(error.localizedDescription)", category: .airplay)
        }
    }

    public func requestCameraCapturePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            return true
        }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    public func promptAccessibilitySettings() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings(for permission: SystemPermission) {
        let urlString = switch permission {
        case .localNetwork:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"
        case .cameraAndCapture:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .bluetooth:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
