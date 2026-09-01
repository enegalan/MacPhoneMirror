import CryptoKit
import Foundation
import Network

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

    func txtAirPlayInfoPlistData() throws -> Data {
        let plist: [String: Any] = [
            "txtAirPlay": encodedTXTRecord(),
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    func fullInfoPlistData() throws -> Data {
        let display: [String: Any] = [
            "width": 402,
            "height": 874,
            "widthPixels": 1206,
            "heightPixels": 2622,
            "refreshRate": 60,
            "maxFPS": 60,
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

enum AirPlayTXTRecordBuilder {
    static let serviceName = "MacPhoneMirror"

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

    private init() {}

    public func publishPIN(_ pin: Int) {
        currentPIN = pin
        displayPIN = String(format: "%04d", pin % 10000)
        AppLogger.info("AirPlay PIN displayed: \(displayPIN ?? "")", category: .airplay)
    }

    public func clearPIN() {
        currentPIN = 0
        displayPIN = nil
    }
}
