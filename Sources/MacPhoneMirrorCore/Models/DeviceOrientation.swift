import Foundation
import CoreGraphics

public enum DeviceOrientation: String, CaseIterable, Codable, Sendable {
    case portrait
    case landscapeLeft
    case landscapeRight
    case portraitUpsideDown
    
    public var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }
    
    public var isPortrait: Bool {
        !isLandscape
    }
    
    /// Rotation angle in radians relative to portrait
    public var rotationAngle: Double {
        switch self {
        case .portrait:
            return 0.0
        case .landscapeLeft:
            return .pi / 2.0
        case .landscapeRight:
            return -.pi / 2.0
        case .portraitUpsideDown:
            return .pi
        }
    }
    
    /// Rotation angle in degrees
    public var rotationDegrees: Double {
        switch self {
        case .portrait:
            return 0.0
        case .landscapeLeft:
            return 90.0
        case .landscapeRight:
            return -90.0
        case .portraitUpsideDown:
            return 180.0
        }
    }
    
    /// Transformed size for a given base portrait size
    public func orientedSize(for baseSize: CGSize) -> CGSize {
        if isLandscape {
            return CGSize(width: baseSize.height, height: baseSize.width)
        } else {
            return baseSize
        }
    }
}
