import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

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
    private var inFlightFrames = 0
    private var pendingTickets: [ObjectIdentifier: InFlightTicket] = [:]
    private let inFlightLock = NSLock()
    private let maxInFlightLowLatency = 5

    public weak var delegate: VideoDecoderDelegate?

    public init() {}

    deinit {
        invalidateSession()
    }

    public func configure(with formatDesc: CMVideoFormatDescription) -> Bool {
        formatDescription = formatDesc
        didLogFirstPixelBuffer = false
        decodeErrorCount = 0
        inFlightLock.lock()
        inFlightFrames = 0
        pendingTickets.removeAll()
        inFlightLock.unlock()
        invalidateSession()

        let destinationPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferOpenGLCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        var outputCallback = VTDecompressionOutputCallbackRecord(
            // swiftlint:disable:next line_length
            decompressionOutputCallback: { decompressionOutputRefCon, sourceFrameRefCon, status, _, imageBuffer, presentationTimeStamp, _ in
                guard let refCon = decompressionOutputRefCon else { return }
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()

                if let sourceFrameRefCon {
                    let ticket = Unmanaged<InFlightTicket>.fromOpaque(sourceFrameRefCon).takeUnretainedValue()
                    decoder.finishTicket(ticket)
                } else {
                    decoder.noteFrameCompleted()
                }

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

        let preferHardware = AppPreferences.enableHardwareDecode
        let decoderSpecification: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: preferHardware,
        ]

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )

        guard status == noErr, let validSession = session else {
            AppLogger.error("Failed to create VTDecompressionSession: \(status)", category: .video)
            return false
        }

        VTSessionSetProperty(validSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        decompressionSession = validSession
        AppLogger.info(
            "VTDecompressionSession created (hardwarePrefer=\(preferHardware))",
            category: .video
        )
        return true
    }

    public func decode(sampleBuffer: CMSampleBuffer) {
        guard let session = decompressionSession else {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if configure(with: formatDesc) {
                    decode(sampleBuffer: sampleBuffer)
                }
            }
            return
        }

        let lowLatency = AppPreferences.lowLatencyMode
        if lowLatency, currentInFlight() >= maxInFlightLowLatency {
            PerformanceMonitor.shared.recordDroppedFrame()
            return
        }

        var flagsOut: VTDecodeInfoFlags = []
        var decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        if !lowLatency {
            decodeFlags.insert(._1xRealTimePlayback)
        }

        let ticket = InFlightTicket()
        inFlightLock.lock()
        pendingTickets[ObjectIdentifier(ticket)] = ticket
        inFlightFrames += 1
        inFlightLock.unlock()

        let start = CFAbsoluteTimeGetCurrent()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: Unmanaged.passUnretained(ticket).toOpaque(),
            infoFlagsOut: &flagsOut
        )

        if status != noErr {
            // Sync reject. Callback may also run; finishTicket is one-shot.
            finishTicket(ticket)
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
        if decodeErrorCount == 1 || decodeErrorCount.isMultiple(of: 120) {
            AppLogger.warning("VT decode callback status: \(status) (count=\(decodeErrorCount))", category: .airplay)
        }
    }

    /// Completes in-flight accounting at most once per DecodeFrame submission.
    fileprivate func finishTicket(_ ticket: InFlightTicket) {
        guard ticket.markCompleted() else { return }
        inFlightLock.lock()
        pendingTickets.removeValue(forKey: ObjectIdentifier(ticket))
        inFlightFrames = max(0, inFlightFrames - 1)
        inFlightLock.unlock()
    }

    fileprivate func noteFrameCompleted() {
        inFlightLock.lock()
        inFlightFrames = max(0, inFlightFrames - 1)
        inFlightLock.unlock()
    }

    private func currentInFlight() -> Int {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return inFlightFrames
    }

    public func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
    }
}

/// One-shot gate so sync DecodeFrame failure and the output callback cannot both decrement.
private final class InFlightTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didComplete else { return false }
        didComplete = true
        return true
    }
}
