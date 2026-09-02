import Foundation

public enum StreamQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case ultra
    case high
    case balanced
    case lowBandwidth

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .ultra:
            "Ultra (Native / 60 FPS)"
        case .high:
            "High (1080p / 60 FPS)"
        case .balanced:
            "Balanced (720p / 60 FPS)"
        case .lowBandwidth:
            "Low Bandwidth (720p / 30 FPS)"
        }
    }

    public var maxFPS: Int {
        switch self {
        case .ultra, .high, .balanced:
            60
        case .lowBandwidth:
            30
        }
    }

    /// The maximum point dimensions advertised to the iPhone during AirPlay negotiation.
    /// These act as a cap: the iPhone will not exceed this resolution.
    public var advertisedSize: CGSize {
        switch self {
        case .ultra:
            CGSize(width: 402, height: 874)
        case .high:
            CGSize(width: 402, height: 874)
        case .balanced, .lowBandwidth:
            CGSize(width: 267, height: 580)
        }
    }

    public var advertisedPixelSize: CGSize {
        switch self {
        case .ultra:
            CGSize(width: 1206, height: 2622)
        case .high:
            CGSize(width: 1080, height: 2340)
        case .balanced, .lowBandwidth:
            CGSize(width: 720, height: 1560)
        }
    }
}

/// Central, persisted configuration for the AirPlay mirroring stream quality.
/// The resolution is negotiated with the iPhone on the next session establishment.
public final class StreamConfiguration: @unchecked Sendable {
    public static let shared = StreamConfiguration()

    private static let qualityKey = "streamQuality"

    public var quality: StreamQuality {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.qualityKey),
                  let quality = StreamQuality(rawValue: raw)
            else { return .ultra }
            return quality
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.qualityKey)
        }
    }

    private init() {}
}
