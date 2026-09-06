@testable import MacPhoneMirrorCore
import CoreVideo
import Testing

// Unit tests for video frame / decoder helpers without a live phone stream.

struct VideoPipelineTests {
    /// Asserts VideoFrame wraps a CVPixelBuffer with correct size and index.
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
