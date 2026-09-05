import CoreGraphics
import Foundation

public enum PhoneModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case iPhone16ProMax = "iPhone 16 Pro Max"
    case iPhone16Pro = "iPhone 16 Pro"
    case iPhone16Plus = "iPhone 16 Plus"
    case iPhone16 = "iPhone 16"
    case iPhone15ProMax = "iPhone 15 Pro Max"
    case iPhone15Pro = "iPhone 15 Pro"
    case iPhone15Plus = "iPhone 15 Plus"
    case iPhone15 = "iPhone 15"
    case iPhone14ProMax = "iPhone 14 Pro Max"
    case iPhone14Pro = "iPhone 14 Pro"
    case iPhone14 = "iPhone 14"
    case iPhone13Pro = "iPhone 13 Pro"
    case iPhone13 = "iPhone 13"
    case iPhoneSE3 = "iPhone SE (3rd generation)"
    case genericModern = "Generic Modern iPhone"

    public var id: String {
        rawValue
    }

    /// Native point resolution (e.g. 393 x 852 for iPhone 15/16 Pro)
    public var pointSize: CGSize {
        switch self {
        case .iPhone16ProMax:
            CGSize(width: 440, height: 956)
        case .iPhone16Pro:
            CGSize(width: 402, height: 874)
        case .iPhone16Plus, .iPhone15Plus, .iPhone14ProMax, .iPhone15ProMax:
            CGSize(width: 430, height: 932)
        case .iPhone16, .iPhone15Pro, .iPhone15, .iPhone14Pro:
            CGSize(width: 393, height: 852)
        case .iPhone14, .iPhone13Pro, .iPhone13:
            CGSize(width: 390, height: 844)
        case .iPhoneSE3:
            CGSize(width: 375, height: 667)
        case .genericModern:
            CGSize(width: 393, height: 852)
        }
    }

    /// Native pixel resolution (e.g. 1179 x 2556)
    public var pixelSize: CGSize {
        let scale = scaleFactor
        return CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    }

    public var scaleFactor: CGFloat {
        switch self {
        case .iPhoneSE3:
            2.0
        default:
            3.0
        }
    }

    public var aspectRatio: CGFloat {
        pointSize.height / pointSize.width
    }

    /// Corner radius for the screen in points
    public var screenCornerRadius: CGFloat {
        switch self {
        case .iPhone16ProMax, .iPhone16Pro:
            56.0
        case .iPhone16Plus, .iPhone16, .iPhone15ProMax, .iPhone15Pro,
             .iPhone15Plus, .iPhone15, .iPhone14ProMax, .iPhone14Pro, .genericModern:
            53.0
        case .iPhone14, .iPhone13Pro, .iPhone13:
            47.0
        case .iPhoneSE3:
            0.0
        }
    }

    /// Hardware bezel corner radius
    public var outerCornerRadius: CGFloat {
        screenCornerRadius + 10.0
    }

    /// Bezel thickness around the screen
    public var bezelThickness: CGFloat {
        switch self {
        case .iPhone16ProMax, .iPhone16Pro:
            3.0
        case .iPhone15ProMax, .iPhone15Pro, .iPhone16, .iPhone16Plus:
            4.0
        case .iPhone15, .iPhone15Plus, .iPhone14ProMax, .iPhone14Pro, .genericModern:
            4.5
        case .iPhone14, .iPhone13Pro, .iPhone13:
            5.5
        case .iPhoneSE3:
            18.0
        }
    }

    /// Top safe area inset in points
    public var topSafeAreaInset: CGFloat {
        switch self {
        case .iPhoneSE3:
            20.0
        case .iPhone14, .iPhone13Pro, .iPhone13:
            47.0
        default:
            59.0
        }
    }

    /// Bottom safe area inset in points
    public var bottomSafeAreaInset: CGFloat {
        switch self {
        case .iPhoneSE3:
            0.0
        default:
            34.0
        }
    }
}
