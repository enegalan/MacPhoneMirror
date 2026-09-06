import CoreGraphics
import CryptoKit
import Foundation
import Network

// Persistent receiver identity (device ID, pairing ID, Ed25519 key) and feature flags.
// iOS caches pairing against this identity; regenerating it forces re-pair / PIN.

struct AirPlayIdentity {
    let deviceID: String
    let pairingID: String
    let signingPrivateKey: Curve25519.Signing.PrivateKey

    static let featuresHex = "0x527FFEE6,0x0"
    static let airplayFlags = "0x84"
    static let statusFlags: UInt64 = 68

    var publicKeyData: Data {
        signingPrivateKey.publicKey.rawRepresentation
    }

    var publicKeyHex: String {
        publicKeyData.map { String(format: "%02x", $0) }.joined()
    }

    var combinedFeatures: UInt64 {
        0x527F_FEE6
    }

    private static let deviceIDKey = "airplay.deviceid"
    private static let privateKeyKey = "airplay.privateKey"
    private static let pairingIDKey = "airplay.pairingID"

    /// Loads persisted device/pairing keys or creates and stores a new identity.
    static func loadOrCreate() -> AirPlayIdentity {
        let defaults = UserDefaults.standard

        if let deviceID = defaults.string(forKey: deviceIDKey),
           let privateKeyData = defaults.data(forKey: privateKeyKey),
           let pairingID = defaults.string(forKey: pairingIDKey),
           let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        {
            return AirPlayIdentity(deviceID: deviceID, pairingID: pairingID, signingPrivateKey: privateKey)
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let uuid = UUID()
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0.prefix(6)) }
        let deviceID = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        let pairingID = UUID().uuidString

        defaults.set(deviceID, forKey: deviceIDKey)
        defaults.set(privateKey.rawRepresentation, forKey: privateKeyKey)
        defaults.set(pairingID, forKey: pairingIDKey)

        return AirPlayIdentity(deviceID: deviceID, pairingID: pairingID, signingPrivateKey: privateKey)
    }

    /// Length-prefixed TXT key=value blob used inside `/info` responses.
    func encodedTXTRecord() -> Data {
        let entries = [
            "deviceid=\(deviceID)",
            "features=\(Self.featuresHex)",
            "flags=\(Self.airplayFlags)",
            "model=AppleTV6,2",
            "srcvers=366.0",
            "vv=2",
            "protovers=1.1",
            "pi=\(pairingID)",
            "pk=\(publicKeyHex)",
            "gid=\(pairingID)",
            "gcgl=0",
            "igl=0",
            "acl=0",
            "rsf=0x0",
            "fn=\(AirPlayTXTRecordBuilder.serviceName)",
        ]

        var data = Data()
        for entry in entries {
            guard let bytes = entry.data(using: .utf8), bytes.count <= 255 else { continue }
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        return data
    }

    /// Binary plist wrapping `txtAirPlay` for qualifier-based GET `/info`.
    func txtAirPlayInfoPlistData() throws -> Data {
        let plist: [String: Any] = [
            "txtAirPlay": encodedTXTRecord(),
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    /// Full receiver capability plist (features, displays, keys) for GET `/info` / SETUP merge.
    func fullInfoPlistData() throws -> Data {
        let config = StreamConfiguration.shared
        let size = config.quality.advertisedSize
        let pixelSize = config.quality.advertisedPixelSize
        let display: [String: Any] = [
            "width": Int(size.width),
            "height": Int(size.height),
            "widthPixels": Int(pixelSize.width),
            "heightPixels": Int(pixelSize.height),
            "refreshRate": config.quality.maxFPS,
            "maxFPS": config.quality.maxFPS,
            "overscanned": false,
            "uuid": pairingID,
        ]
        let plist: [String: Any] = [
            "deviceID": deviceID,
            "features": combinedFeatures,
            "model": "AppleTV6,2",
            "name": AirPlayTXTRecordBuilder.serviceName,
            "pi": pairingID,
            "pk": publicKeyData,
            "sourceVersion": "366.0",
            "statusFlags": Self.statusFlags,
            "vv": 2,
            "keepAliveLowPower": true,
            "keepAliveSendStatsAsBody": true,
            "macAddress": deviceID,
            "displays": [display],
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }
}

public enum AirPlayTXTRecordBuilder {
    private static let serviceNameKey = "airplay.serviceName"

    public static var serviceName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: serviceNameKey)
            if let stored, !stored.isEmpty {
                return stored
            }
            return AppInfo.displayName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: serviceNameKey)
        }
    }

    /// Builds the Bonjour TXT record advertised on `_airplay._tcp`.
    static func makeRecord(identity: AirPlayIdentity) -> NWTXTRecord {
        var record = NWTXTRecord()
        record["deviceid"] = identity.deviceID
        record["features"] = AirPlayIdentity.featuresHex
        record["flags"] = AirPlayIdentity.airplayFlags
        record["model"] = "AppleTV6,2"
        record["srcvers"] = "366.0"
        record["vv"] = "2"
        record["protovers"] = "1.1"
        record["pi"] = identity.pairingID
        record["pk"] = identity.publicKeyHex
        record["gid"] = identity.pairingID
        record["gcgl"] = "0"
        record["igl"] = "0"
        record["acl"] = "0"
        record["rsf"] = "0x0"
        record["fn"] = serviceName
        return record
    }
}

public final class AirPlayPairingState: ObservableObject, @unchecked Sendable {
    public static let shared = AirPlayPairingState()

    @Published public private(set) var displayPIN: String?
    public private(set) var currentPIN: Int = 0

    /// Private singleton initializer.
    private init() {}

    /// Publishes a zero-padded PIN for the pairing UI.
    public func publishPIN(_ pin: Int) {
        currentPIN = pin
        displayPIN = String(format: "%04d", pin % 10000)
        AppLogger.info("AirPlay PIN displayed: \(displayPIN ?? "")", category: .airplay)
    }

    /// Clears the displayed pairing PIN.
    public func clearPIN() {
        currentPIN = 0
        displayPIN = nil
    }
}
