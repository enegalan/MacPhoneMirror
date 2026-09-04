import AppKit
import CoreBluetooth
import Foundation
import Network

public enum SystemPermission: String, CaseIterable, Identifiable, Sendable {
    case localNetwork = "Local Network"
    case bluetooth = "Bluetooth"

    public var id: String {
        rawValue
    }

    public var reasonDescription: String {
        switch self {
        case .localNetwork:
            "Required to discover iPhones advertising AirPlay / Bonjour services on your local Wi-Fi network."
        case .bluetooth:
            "Required to pair \(AppInfo.displayName) as a Bluetooth HID device for mouse and keyboard control."
        }
    }
}

public final class PermissionManager: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    public static let shared = PermissionManager()

    private var _localNetworkAuthorized = false
    private var _bluetoothAuthorized = false
    private let lock = NSLock()
    private var localNetworkBrowser: NWBrowser?
    private var bluetoothProbe: CBCentralManager?

    override private init() {
        super.init()
    }

    public func checkPermissionStatus(_ permission: SystemPermission) -> Bool {
        switch permission {
        case .bluetooth:
            lock.lock()
            defer { lock.unlock() }
            return _bluetoothAuthorized
        case .localNetwork:
            lock.lock()
            defer { lock.unlock() }
            return _localNetworkAuthorized
        }
    }

    public func requestBluetoothPermission() {
        if bluetoothProbe == nil {
            bluetoothProbe = CBCentralManager(delegate: self, queue: .main)
        }
    }

    public func centralManagerDidUpdateState(_: CBCentralManager) {
        lock.lock()
        _bluetoothAuthorized = CBManager.authorization == .allowedAlways
        lock.unlock()
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
        requestBluetoothPermission()
        do {
            try await NetworkStreamReceiver.shared.start()
        } catch {
            AppLogger.error("Failed to start AirPlay advertising: \(error.localizedDescription)", category: .airplay)
        }
    }

    public func openSystemSettings(for permission: SystemPermission) {
        let urlString = switch permission {
        case .localNetwork:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"
        case .bluetooth:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
