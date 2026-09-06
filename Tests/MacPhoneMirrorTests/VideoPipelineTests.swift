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

    /// numOfArrays lives at zero-based offset 22 in HEVCDecoderConfigurationRecord.
    @Test func parseHVCCReadsNumArraysAtOffset22() {
        var hvcc = Data(count: 23)
        hvcc[0] = 1 // configurationVersion

        let vps = Data([0x40, 0x01, 0x0C, 0x01])
        let sps = Data([0x42, 0x01, 0x01, 0x01])
        let pps = Data([0x44, 0x01, 0xC0, 0xF2])

        // Intentionally wrong if reader starts at offset 23: first array type would be treated as count.
        hvcc[22] = 3
        appendHVCCArray(to: &hvcc, nalType: 32, nals: [vps])
        appendHVCCArray(to: &hvcc, nalType: 33, nals: [sps])
        appendHVCCArray(to: &hvcc, nalType: 34, nals: [pps])

        let decoder = AirPlayH264Decoder()
        let sets = decoder.parseHVCC(hvcc)
        #expect(sets?.count == 3)
        #expect(sets?[0] == vps)
        #expect(sets?[1] == sps)
        #expect(sets?[2] == pps)
    }
}

private func appendHVCCArray(to data: inout Data, nalType: UInt8, nals: [Data]) {
    data.append(nalType) // array_completeness=0, nal type in low 6 bits
    data.append(UInt8((nals.count >> 8) & 0xFF))
    data.append(UInt8(nals.count & 0xFF))
    for nal in nals {
        data.append(UInt8((nal.count >> 8) & 0xFF))
        data.append(UInt8(nal.count & 0xFF))
        data.append(nal)
    }
}
