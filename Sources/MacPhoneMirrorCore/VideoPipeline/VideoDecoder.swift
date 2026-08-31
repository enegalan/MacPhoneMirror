import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

public protocol VideoDecoderDelegate: AnyObject, Sendable {
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func decoder(_ decoder: VideoDecoder, didFailWithError error: Error)
}

public final class VideoDecoder: @unchecked Sendable {
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let queue = DispatchQueue(label: "com.macphonemirror.videodecoder", qos: .userInteractive)
    private var didLogFirstPixelBuffer = false
    private var decodeErrorCount = 0
    
    public weak var delegate: VideoDecoderDelegate?
    
    public init() {}
    
    deinit {
        invalidateSession()
    }
    
    public func configure(with formatDesc: CMVideoFormatDescription) -> Bool {
        self.formatDescription = formatDesc
        didLogFirstPixelBuffer = false
        decodeErrorCount = 0
        invalidateSession()
        
        let destinationPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferOpenGLCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (decompressionOutputRefCon, _, status, _, imageBuffer, presentationTimeStamp, _) in
                guard let refCon = decompressionOutputRefCon else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
                guard status == noErr, let imageBuffer else {
                    if status != noErr {
                        decoder.noteDecodeError(status)
                    }
                    return
                }
                decoder.handleDecodedFrame(imageBuffer, pts: presentationTimeStamp)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )
        
        guard status == noErr, let validSession = session else {
            AppLogger.error("Failed to create VTDecompressionSession: \(status)", category: .video)
            return false
        }
        
        // Enable hardware real-time mode
        VTSessionSetProperty(validSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        self.decompressionSession = validSession
        AppLogger.info("VTDecompressionSession created with hardware acceleration", category: .video)
        return true
    }
    
    public func decode(sampleBuffer: CMSampleBuffer) {
        guard let session = decompressionSession else {
            // If format description changed or not initialized, attempt setup
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if configure(with: formatDesc) {
                    decode(sampleBuffer: sampleBuffer)
                }
            }
            return
        }
        
        var flagsOut: VTDecodeInfoFlags = []
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._1xRealTimePlayback]
        
        let start = CFAbsoluteTimeGetCurrent()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        
        if status != noErr {
            AppLogger.warning("VTDecompressionSessionDecodeFrame status: \(status)", category: .airplay)
            PerformanceMonitor.shared.recordDroppedFrame()
        } else {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            PerformanceMonitor.shared.recordDecodeTime(elapsed)
        }
    }
    
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        if !didLogFirstPixelBuffer {
            didLogFirstPixelBuffer = true
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            AppLogger.info("VTDecompressionSession first pixel buffer (\(width)x\(height))", category: .airplay)
        }
        delegate?.decoder(self, didOutputPixelBuffer: pixelBuffer, presentationTime: pts)
    }

    fileprivate func noteDecodeError(_ status: OSStatus) {
        decodeErrorCount += 1
        if decodeErrorCount == 1 || decodeErrorCount % 120 == 0 {
            AppLogger.warning("VT decode callback status: \(status) (count=\(decodeErrorCount))", category: .airplay)
        }
    }
    
    public func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
    }
}
