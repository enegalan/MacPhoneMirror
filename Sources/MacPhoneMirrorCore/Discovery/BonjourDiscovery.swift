import Combine
import Foundation
import Network

public final class BonjourDiscovery: DeviceDiscovery, @unchecked Sendable {
    private let devicesSubject = CurrentValueSubject<[PhoneDevice], Never>([])
    private var browsers: [NWBrowser] = []
    private var resultsByBrowser: [ObjectIdentifier: Set<NWBrowser.Result>] = [:]
    private let lock = NSLock()
    private var _isScanning: Bool = false
    private let queue = DispatchQueue(label: "com.macphonemirror.bonjour.discovery")

    public var devices: [PhoneDevice] {
        devicesSubject.value
    }

    public var devicesPublisher: AnyPublisher<[PhoneDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    public var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    public init() {}

    public func start() {
        lock.lock()
        guard !_isScanning else {
            lock.unlock()
            return
        }
        _isScanning = true
        resultsByBrowser.removeAll()
        lock.unlock()

        let serviceTypes = ["_companion-link._tcp", "_apple-mobdev2._tcp", "_airplay._tcp"]
        for serviceType in serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
            let parameters = NWParameters()
            let browser = NWBrowser(for: descriptor, using: parameters)

            browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                guard let self, let browser else { return }
                storeResults(results, for: browser)
            }

            browser.start(queue: queue)
            browsers.append(browser)
        }
        AppLogger.info("Started multi-service Bonjour discovery for iOS devices", category: .network)
    }

    public func stop() {
        lock.lock()
        _isScanning = false
        resultsByBrowser.removeAll()
        lock.unlock()

        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        AppLogger.info("Stopped Bonjour discovery", category: .network)
    }

    private func storeResults(_ results: Set<NWBrowser.Result>, for browser: NWBrowser) {
        lock.lock()
        resultsByBrowser[ObjectIdentifier(browser)] = results
        let merged = resultsByBrowser.values.reduce(into: Set<NWBrowser.Result>()) { partial, batch in
            partial.formUnion(batch)
        }
        lock.unlock()
        publishDevices(from: merged)
    }

    private func publishDevices(from results: Set<NWBrowser.Result>) {
        var phones: [PhoneDevice] = []
        var seenKeys = Set<String>()

        for result in results {
            guard case let .service(serviceName, _, _, _) = result.endpoint else { continue }
            guard let displayName = resolveDisplayName(
                serviceName: serviceName,
                metadata: result.metadata
            ) else { continue }
            guard displayName != AirPlayTXTRecordBuilder.serviceName else { continue }

            let key = DeviceDiscoveryFilter.normalizedDeviceKey(from: displayName)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            let model = mapModel(from: result.metadata)
            let device = PhoneDevice(
                name: displayName,
                id: "bonjour-\(key)",
                model: model,
                connectionType: .wifi,
                isAvailable: true,
                isPairedForControl: false
            )
            phones.append(device)
        }

        devicesSubject.send(phones)
    }

    private func resolveDisplayName(serviceName: String, metadata: NWBrowser.Result.Metadata) -> String? {
        if case let .bonjour(txtRecord) = metadata {
            if let model = txtRecord["model"]?.lowercased(),
               model.contains("appletv") || model.contains("audioaccessory") || model.contains("mac")
            {
                return nil
            }

            if let friendlyName = txtRecord["fn"] ?? txtRecord["name"],
               DeviceDiscoveryFilter.isLikelyPhoneName(friendlyName)
            {
                return friendlyName
            }
        }

        if DeviceDiscoveryFilter.isLikelyPhoneName(serviceName) {
            return serviceName
        }

        return nil
    }

    private func mapModel(from metadata: NWBrowser.Result.Metadata) -> PhoneModel {
        guard case let .bonjour(txtRecord) = metadata,
              let modelID = txtRecord["model"]?.lowercased()
        else {
            return .iPhone16Pro
        }

        if modelID.contains("iphone16") || modelID.contains("iphone17") {
            return .iPhone16Pro
        }
        if modelID.contains("iphone15") || modelID.contains("iphone14") {
            return .iPhone16Pro
        }
        if modelID.contains("iphone13") || modelID.contains("iphone12") {
            return .iPhone13
        }
        if modelID.contains("iphonese") {
            return .iPhoneSE3
        }

        return .iPhone16Pro
    }
}
