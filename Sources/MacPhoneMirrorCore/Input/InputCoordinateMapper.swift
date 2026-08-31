import Foundation
import CoreGraphics

public protocol InputCoordinateMapper: Sendable {
    func map(point: CGPoint, in viewportSize: CGSize, device: PhoneDevice, orientation: DeviceOrientation) -> CGPoint?
    func mapToNativeResolution(point: CGPoint, in viewportSize: CGSize, device: PhoneDevice, orientation: DeviceOrientation) -> CGPoint?
}

public struct StandardCoordinateMapper: InputCoordinateMapper {
    public init() {}
    
    /// Maps a point from the macOS view coordinate space to normalized iPhone coordinates `(0.0...1.0, 0.0...1.0)`.
    /// Returns nil if the click is outside the active screen display area (e.g. in letterboxing or outer bezel).
    public func map(
        point: CGPoint,
        in viewportSize: CGSize,
        device: PhoneDevice,
        orientation: DeviceOrientation
    ) -> CGPoint? {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }
        
        let orientedDeviceSize = orientation.orientedSize(for: device.screenSize)
        let targetAspect = orientedDeviceSize.width / orientedDeviceSize.height
        let viewAspect = viewportSize.width / viewportSize.height
        
        var renderRect = CGRect.zero
        
        if viewAspect > targetAspect {
            // View is wider than device -> Pillarbox (bars on left and right)
            let renderHeight = viewportSize.height
            let renderWidth = renderHeight * targetAspect
            let originX = (viewportSize.width - renderWidth) / 2.0
            renderRect = CGRect(x: originX, y: 0, width: renderWidth, height: renderHeight)
        } else {
            // View is taller than device -> Letterbox (bars on top and bottom)
            let renderWidth = viewportSize.width
            let renderHeight = renderWidth / targetAspect
            let originY = (viewportSize.height - renderHeight) / 2.0
            renderRect = CGRect(x: 0, y: originY, width: renderWidth, height: renderHeight)
        }
        
        guard renderRect.contains(point) else {
            return nil
        }
        
        // Relative normalized coordinates within the active render rect
        let normX = (point.x - renderRect.origin.x) / renderRect.width
        let normY = (point.y - renderRect.origin.y) / renderRect.height
        
        // Transform normalized coordinates based on device orientation
        switch orientation {
        case .portrait:
            return CGPoint(x: normX, y: normY)
        case .landscapeLeft:
            return CGPoint(x: 1.0 - normY, y: normX)
        case .landscapeRight:
            return CGPoint(x: normY, y: 1.0 - normX)
        case .portraitUpsideDown:
            return CGPoint(x: 1.0 - normX, y: 1.0 - normY)
        }
    }
    
    /// Maps a point from the macOS view to exact native iPhone pixel coordinates (e.g. (450, 1200) on a 1179 x 2556 screen)
    public func mapToNativeResolution(
        point: CGPoint,
        in viewportSize: CGSize,
        device: PhoneDevice,
        orientation: DeviceOrientation
    ) -> CGPoint? {
        guard let normalized = map(point: point, in: viewportSize, device: device, orientation: orientation) else {
            return nil
        }
        
        let nativeSize = device.model.pixelSize
        return CGPoint(
            x: normalized.x * nativeSize.width,
            y: normalized.y * nativeSize.height
        )
    }
}
