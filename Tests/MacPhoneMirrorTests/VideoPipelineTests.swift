@testable import MacPhoneMirrorCore
import CoreGraphics
import CoreVideo
import Testing

struct VideoPipelineTests {
    @Test func performanceMonitorCalculations() {
        let monitor = PerformanceMonitor()
        monitor.reset()

        let resolution = CGSize(width: 1179, height: 2556)
        for _ in 0 ..< 10 {
            monitor.recordFrameReceived(resolution: resolution)
            monitor.recordDecodeTime(2.5)
            monitor.recordRenderTime(1.1)
        }
        monitor.recordDroppedFrame()

        let stats = monitor.currentStatistics()
        #expect(stats.totalFrames == 10)
        #expect(stats.droppedFrames == 1)
        #expect(stats.resolution == resolution)
        #expect(stats.decodeTimeMs > 0)
        #expect(stats.renderTimeMs > 0)
        #expect(stats.totalLatencyMs > 0)
        #expect(stats.dropRatePercentage > 0)
    }

    @Test func videoFrameCreation() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            100,
            200,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        #expect(pixelBuffer != nil)
        if let buffer = pixelBuffer {
            let frame = VideoFrame(pixelBuffer: buffer, orientation: .portrait, frameIndex: 42)
            #expect(frame.width == 100)
            #expect(frame.height == 200)
            #expect(frame.frameIndex == 42)
        }
    }
}
