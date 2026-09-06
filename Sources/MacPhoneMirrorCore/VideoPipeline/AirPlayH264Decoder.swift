import CoreMedia
import Foundation
import QuartzCore
import VideoToolbox

// VideoToolbox H.264 (and related) decode path for AirPlay NALUs into CVPixelBuffers.
// Feeds NetworkStreamReceiver / Metal renderer; separate from USB AVCapture frames.

final class AirPlayH264Decoder: @unchecked Sendable {
    private enum Codec {
        case h264
        case hevc
    }

    weak var delegate: VideoDecoderDelegate?

    private let decoder = VideoDecoder()
    private var formatDescription: CMVideoFormatDescription?
    private var pendingParameterSets = Data()
    private var lastSPS = Data()
    private var lastPPS = Data()
    private var lastVPS = Data()
    private var waitingForIDR = true
    private var hasLoggedFirstFrame = false
    private var hasLoggedDecodeSkip = false
    private var hasLoggedWaitingForIDR = false
    private var codec: Codec = .h264

    /// Owns a VideoDecoder and forwards its delegate callbacks to this instance.
    init() {
        decoder.delegate = self
    }

    /// Clears parameter-set state and invalidates the VT session for a fresh stream.
    func reset() {
        pendingParameterSets.removeAll(keepingCapacity: false)
        formatDescription = nil
        lastSPS = Data()
        lastPPS = Data()
        lastVPS = Data()
        waitingForIDR = true
        hasLoggedFirstFrame = false
        hasLoggedDecodeSkip = false
        hasLoggedWaitingForIDR = false
        codec = .h264
        decoder.invalidateSession()
    }

    /// Marks screen-off pause without forcing IDR wait — unlock often resumes with P-frames.
    func noteStreamSuspended() {
        // Keep decoder state. Screen-off only pauses new IDRs from the client;
        // do not force an IDR wait — after unlock iPhone often continues with P-frames.
        AppLogger.info("Mirror decoder marked suspended", category: .airplay)
    }

    /// Clears IDR wait so decoding continues immediately after screen unlock.
    func noteStreamResumed() {
        // Session still valid: resume decoding immediately.
        waitingForIDR = false
        hasLoggedWaitingForIDR = false
        AppLogger.info("Mirror video resumed; continuing decode", category: .airplay)
    }

    /// Parses avcC or falls back to SPS/PPS ingest to install an H.264 format description.
    func ingestAVCC(_ payload: Data) {
        guard payload.count > 8, payload[payload.startIndex] == 0x01 else {
            ingestParameterSets(payload)
            return
        }

        let bytes = [UInt8](payload)
        var offset = 5
        let spsCount = Int(bytes[offset] & 0x1F)
        offset += 1

        var parameterSets: [Data] = []
        for _ in 0 ..< spsCount {
            guard offset + 2 <= bytes.count else { return }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard length > 0, offset + length <= bytes.count else { return }
            parameterSets.append(Data(bytes[offset ..< (offset + length)]))
            offset += length
        }

        guard offset < bytes.count else { return }
        let ppsCount = Int(bytes[offset])
        offset += 1

        for _ in 0 ..< ppsCount {
            guard offset + 2 <= bytes.count else { return }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard length > 0, offset + length <= bytes.count else { return }
            parameterSets.append(Data(bytes[offset ..< (offset + length)]))
            offset += length
        }

        guard installFormatDescription(from: parameterSets) else { return }
        AppLogger.info("AirPlay avcC format description ready (\(payload.count) bytes)", category: .airplay)
    }

    /// Extracts SPS/PPS; keeps VT session when unchanged after unlock, else reconfigures and waits for IDR.
    func ingestParameterSets(_ payload: Data) {
        guard payload.count >= 11 else {
            AppLogger.warning("AirPlay SPS/PPS packet too short (\(payload.count) bytes)", category: .airplay)
            return
        }

        let bytes = [UInt8](payload)
        let spsSize = Int(bytes[6]) << 8 | Int(bytes[7])
        guard spsSize > 0, spsSize + 11 + 2 <= bytes.count else {
            let preview = payload.prefix(min(payload.count, 12))
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
            AppLogger.warning("AirPlay SPS/PPS invalid SPS size \(spsSize), header=\(preview)", category: .airplay)
            return
        }

        let sps = Data(bytes[8 ..< (8 + spsSize)])
        let ppsSizeOffset = spsSize + 9
        let ppsSize = Int(bytes[ppsSizeOffset]) << 8 | Int(bytes[ppsSizeOffset + 1])
        let ppsStart = spsSize + 11
        guard ppsSize > 0, ppsStart + ppsSize <= bytes.count else {
            AppLogger.warning("AirPlay SPS/PPS invalid PPS size \(ppsSize)", category: .airplay)
            return
        }

        let pps = Data(bytes[ppsStart ..< (ppsStart + ppsSize)])
        pendingParameterSets = encodeAVCCNALs([sps, pps])

        if sps == lastSPS, pps == lastPPS, formatDescription != nil {
            // Same codec config after screen unlock: keep VT session and keep decoding.
            waitingForIDR = false
            hasLoggedWaitingForIDR = false
            AppLogger.info("AirPlay SPS/PPS unchanged; keeping decoder session", category: .airplay)
            return
        }

        if installFormatDescription(from: [sps, pps]) {
            lastSPS = sps
            lastPPS = pps
            waitingForIDR = true
            hasLoggedWaitingForIDR = false
            AppLogger.info("AirPlay SPS/PPS ready (sps=\(spsSize), pps=\(ppsSize))", category: .airplay)
        } else {
            let spsHeader = sps.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")
            let ppsHeader = pps.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")
            AppLogger.warning(
                "AirPlay SPS/PPS format description failed (sps=\(spsSize) [\(spsHeader)], pps=\(ppsSize) [\(ppsHeader)])",
                category: .airplay
            )
        }
    }

    /// Ingest AirPlay HEVC config payload that contains the `hvc1` fourcc.
    func ingestHEVCConfig(_ payload: Data) {
        guard let hvccStart = payload.range(of: Data([0x68, 0x76, 0x63, 0x31]))?.upperBound else {
            AppLogger.warning("HEVC config missing hvc1 fourcc (\(payload.count) bytes)", category: .airplay)
            return
        }

        let hvcc = Data(payload[hvccStart...])
        guard let parameterSets = parseHVCC(hvcc), parameterSets.count >= 3 else {
            // Fallback: length-prefixed VPS/SPS/PPS after a short header (mirrors H.264 layout).
            if let fallback = parseHEVCLengthPrefixed(payload) {
                installHEVC(parameterSets: fallback)
            } else {
                AppLogger.warning("HEVC config parse failed (\(payload.count) bytes)", category: .airplay)
            }
            return
        }
        installHEVC(parameterSets: parameterSets)
    }

    /// Builds a CMSampleBuffer from AVCC NALs and submits it once format + IDR gates pass.
    func decodeVideoPayload(_ payload: Data, prependParameterSets: Bool) {
        var frameData = Data()
        if prependParameterSets, !pendingParameterSets.isEmpty {
            frameData.append(pendingParameterSets)
            pendingParameterSets.removeAll(keepingCapacity: false)
        }
        frameData.append(payload)

        guard formatDescription != nil else {
            if !hasLoggedDecodeSkip {
                hasLoggedDecodeSkip = true
                AppLogger.warning(
                    "AirPlay \(codec == .hevc ? "HEVC" : "H264") decode skipped: no format description yet "
                        + "(\(frameData.count) bytes)",
                    category: .airplay
                )
            }
            return
        }

        guard let avcc = rebuildAVCC(from: frameData) else {
            return
        }

        let nals = extractNALUnits(from: avcc)
        let hasIDR: Bool = switch codec {
        case .h264:
            nals.contains { (($0.first ?? 0) & 0x1F) == 5 }
        case .hevc:
            nals.contains {
                let type = (Int($0.first ?? 0) >> 1) & 0x3F
                return type == 19 || type == 20 || type == 21
            }
        }

        if waitingForIDR, !hasIDR {
            if !hasLoggedWaitingForIDR {
                hasLoggedWaitingForIDR = true
                AppLogger.info(
                    "AirPlay \(codec == .hevc ? "HEVC" : "H264") skipping frames until IDR (new format)",
                    category: .airplay
                )
            }
            return
        }

        if hasIDR {
            waitingForIDR = false
            hasLoggedWaitingForIDR = false
        }

        if !hasLoggedFirstFrame {
            let types: String = switch codec {
            case .h264:
                nals.map { String(($0.first ?? 0) & 0x1F) }.joined(separator: ",")
            case .hevc:
                nals.map { String((Int($0.first ?? 0) >> 1) & 0x3F) }.joined(separator: ",")
            }
            AppLogger.info(
                "AirPlay \(codec == .hevc ? "HEVC" : "H264") NAL types in first frame: [\(types)]",
                category: .airplay
            )
        }

        guard let sampleBuffer = makeSampleBuffer(fromAVCC: avcc) else {
            AppLogger.warning(
                "AirPlay \(codec == .hevc ? "HEVC" : "H264") sample buffer creation failed "
                    + "(\(frameData.count) bytes)",
                category: .airplay
            )
            return
        }

        if !hasLoggedFirstFrame {
            hasLoggedFirstFrame = true
            AppLogger.info(
                "AirPlay \(codec == .hevc ? "HEVC" : "H264") first frame (\(frameData.count) bytes)",
                category: .airplay
            )
        }

        decoder.decode(sampleBuffer: sampleBuffer)
    }

    /// Applies VPS/SPS/PPS; keeps session when unchanged, else reconfigures HEVC and waits for IDR.
    private func installHEVC(parameterSets: [Data]) {
        guard parameterSets.count >= 3 else { return }
        let vps = parameterSets[0]
        let sps = parameterSets[1]
        let pps = parameterSets[2]

        if vps == lastVPS, sps == lastSPS, pps == lastPPS, formatDescription != nil, codec == .hevc {
            waitingForIDR = false
            hasLoggedWaitingForIDR = false
            AppLogger.info("AirPlay HEVC parameter sets unchanged; keeping decoder session", category: .airplay)
            return
        }

        pendingParameterSets = encodeAVCCNALs([vps, sps, pps])
        if installHEVCFormatDescription(vps: vps, sps: sps, pps: pps) {
            lastVPS = vps
            lastSPS = sps
            lastPPS = pps
            codec = .hevc
            waitingForIDR = true
            hasLoggedWaitingForIDR = false
            hasLoggedFirstFrame = false
            AppLogger.info(
                "AirPlay HEVC ready (vps=\(vps.count), sps=\(sps.count), pps=\(pps.count))",
                category: .airplay
            )
        } else {
            AppLogger.warning("AirPlay HEVC format description failed", category: .airplay)
        }
    }

    /// Parses hvcC arrays into VPS/SPS/PPS NALs.
    private func parseHVCC(_ hvcc: Data) -> [Data]? {
        // hvcc payload starts at configurationVersion (after fourcc already stripped by caller).
        let bytes = [UInt8](hvcc)
        guard bytes.count > 23, bytes[0] == 1 else { return nil }

        var offset = 23 // configurationVersion through lengthSizeMinusOne
        guard offset < bytes.count else { return nil }
        let numArrays = Int(bytes[offset])
        offset += 1

        var vps: Data?
        var sps: Data?
        var pps: Data?

        for _ in 0 ..< numArrays {
            guard offset + 3 <= bytes.count else { return nil }
            let nalType = Int(bytes[offset] & 0x3F)
            offset += 1
            let nalCount = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            for _ in 0 ..< nalCount {
                guard offset + 2 <= bytes.count else { return nil }
                let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                offset += 2
                guard length > 0, offset + length <= bytes.count else { return nil }
                let nal = Data(bytes[offset ..< (offset + length)])
                offset += length
                switch nalType {
                case 32: vps = nal
                case 33: sps = nal
                case 34: pps = nal
                default: break
                }
            }
        }

        guard let vps, let sps, let pps else { return nil }
        return [vps, sps, pps]
    }

    /// Fallback HEVC layout: length-prefixed VPS/SPS/PPS after the hvc1 fourcc.
    private func parseHEVCLengthPrefixed(_ payload: Data) -> [Data]? {
        // Try layout similar to H.264: sizes at fixed offsets after fourcc.
        guard let fourcc = payload.range(of: Data([0x68, 0x76, 0x63, 0x31])) else { return nil }
        var offset = fourcc.upperBound
        let bytes = [UInt8](payload)
        var nals: [Data] = []
        while offset + 2 <= bytes.count, nals.count < 3 {
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard length > 0, offset + length <= bytes.count else { break }
            nals.append(Data(bytes[offset ..< (offset + length)]))
            offset += length
        }
        guard nals.count >= 3 else { return nil }
        return Array(nals.prefix(3))
    }

    /// Creates an HEVC CMVideoFormatDescription and reconfigures VideoDecoder.
    private func installHEVCFormatDescription(vps: Data, sps: Data, pps: Data) -> Bool {
        var description: CMFormatDescription?
        var status: OSStatus = -1

        vps.withUnsafeBytes { vpsBytes in
            sps.withUnsafeBytes { spsBytes in
                pps.withUnsafeBytes { ppsBytes in
                    guard let vpsBase = vpsBytes.baseAddress,
                          let spsBase = spsBytes.baseAddress,
                          let ppsBase = ppsBytes.baseAddress
                    else { return }
                    var pointers: [UnsafePointer<UInt8>] = [
                        vpsBase.assumingMemoryBound(to: UInt8.self),
                        spsBase.assumingMemoryBound(to: UInt8.self),
                        ppsBase.assumingMemoryBound(to: UInt8.self),
                    ]
                    var sizes = [vps.count, sps.count, pps.count]
                    status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: &pointers,
                        parameterSetSizes: &sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &description
                    )
                }
            }
        }

        guard status == noErr, let description else { return false }
        formatDescription = description
        _ = decoder.configure(with: description)
        return true
    }

    /// Creates an H.264 CMVideoFormatDescription from SPS/PPS and reconfigures VideoDecoder.
    private func installFormatDescription(from parameterSets: [Data]) -> Bool {
        guard parameterSets.count >= 2 else { return false }

        let sps = parameterSets[0]
        let pps = parameterSets[1]
        var description: CMFormatDescription?
        var status: OSStatus = -1

        sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                guard let spsBase = spsBytes.baseAddress, let ppsBase = ppsBytes.baseAddress else { return }
                var pointers: [UnsafePointer<UInt8>] = [
                    spsBase.assumingMemoryBound(to: UInt8.self),
                    ppsBase.assumingMemoryBound(to: UInt8.self),
                ]
                var sizes = [sps.count, pps.count]
                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            }
        }

        guard status == noErr, let description else { return false }
        formatDescription = description
        codec = .h264
        _ = decoder.configure(with: description)
        return true
    }

    /// Splits length-prefixed AVCC into individual NAL unit Data blobs.
    private func extractNALUnits(from avcc: Data) -> [Data] {
        var nals: [Data] = []
        var offset = 0
        let bytes = [UInt8](avcc)

        while offset + 4 <= bytes.count {
            let length = Int(bytes[offset]) << 24
                | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
            offset += 4
            guard length > 0, offset + length <= bytes.count else { break }
            nals.append(Data(bytes[offset ..< (offset + length)]))
            offset += length
        }

        return nals
    }

    /// Wraps AVCC bytes in a timed CMSampleBuffer using the current format description.
    private func makeSampleBuffer(fromAVCC avcc: Data) -> CMSampleBuffer? {
        guard let formatDescription else { return nil }

        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let replaceStatus = avcc.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(CACurrentMediaTime() * 600), timescale: 600),
            decodeTimeStamp: .invalid
        )
        let sampleSize = avcc.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [sampleSize],
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
    }

    /// Encodes NAL units as 4-byte big-endian length + payload (AVCC).
    private func encodeAVCCNALs(_ nals: [Data]) -> Data {
        var data = Data()
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { rawBuffer in
                data.append(contentsOf: rawBuffer)
            }
            data.append(nal)
        }
        return data
    }

    /// Validates NAL forbidden-bit and re-encodes extracted units as clean AVCC.
    private func rebuildAVCC(from data: Data) -> Data? {
        let nals = extractNALUnits(from: data)
        guard !nals.isEmpty else { return nil }

        for nal in nals {
            guard (nal.first ?? 0x80) & 0x80 == 0 else { return nil }
        }

        return encodeAVCCNALs(nals)
    }
}

extension AirPlayH264Decoder: VideoDecoderDelegate {
    /// Forwards decoded pixel buffers to the outer AirPlay receiver delegate.
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        delegate?.decoder(decoder, didOutputPixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    /// Forwards VideoToolbox failures to the outer AirPlay receiver delegate.
    func decoder(_ decoder: VideoDecoder, didFailWithError error: Error) {
        delegate?.decoder(decoder, didFailWithError: error)
    }
}
