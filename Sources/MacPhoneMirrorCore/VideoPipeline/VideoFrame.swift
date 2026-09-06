import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

// Sendable frame envelope (pixel buffer, orientation, timestamps) published to UI.

public struct VideoFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let presentationTimestamp: CMTime
    public let orientation: DeviceOrientation
    public let frameIndex: UInt64
    public let captureTimestamp: DispatchTime

    /// Bundles a CVPixelBuffer with timing and orientation for UI/renderer consumers.
    public init(
        pixelBuffer: CVPixelBuffer,
        presentationTimestamp: CMTime = .invalid,
        orientation: DeviceOrientation = .portrait,
        frameIndex: UInt64 = 0,
        captureTimestamp: DispatchTime = .now()
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTimestamp = presentationTimestamp
        self.orientation = orientation
        self.frameIndex = frameIndex
        self.captureTimestamp = captureTimestamp
    }

    public var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }

    public var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }

    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    public var pixelFormat: OSType {
        CVPixelBufferGetPixelFormatType(pixelBuffer)
    }
}
