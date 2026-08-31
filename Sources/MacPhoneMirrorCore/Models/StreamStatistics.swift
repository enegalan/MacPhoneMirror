import Foundation
import CoreGraphics

public struct StreamStatistics: Sendable, Equatable {
    public var currentFPS: Double
    public var targetFPS: Double
    public var decodeTimeMs: Double
    public var renderTimeMs: Double
    public var totalLatencyMs: Double
    public var droppedFrames: UInt64
    public var totalFrames: UInt64
    public var bitRateMbps: Double
    public var resolution: CGSize
    public var isHardwareAccelerated: Bool
    
    public init(
        currentFPS: Double = 0.0,
        targetFPS: Double = 60.0,
        decodeTimeMs: Double = 0.0,
        renderTimeMs: Double = 0.0,
        totalLatencyMs: Double = 0.0,
        droppedFrames: UInt64 = 0,
        totalFrames: UInt64 = 0,
        bitRateMbps: Double = 0.0,
        resolution: CGSize = .zero,
        isHardwareAccelerated: Bool = true
    ) {
        self.currentFPS = currentFPS
        self.targetFPS = targetFPS
        self.decodeTimeMs = decodeTimeMs
        self.renderTimeMs = renderTimeMs
        self.totalLatencyMs = totalLatencyMs
        self.droppedFrames = droppedFrames
        self.totalFrames = totalFrames
        self.bitRateMbps = bitRateMbps
        self.resolution = resolution
        self.isHardwareAccelerated = isHardwareAccelerated
    }
    
    public var dropRatePercentage: Double {
        guard totalFrames > 0 else { return 0.0 }
        return (Double(droppedFrames) / Double(totalFrames + droppedFrames)) * 100.0
    }
}
