import CoreMedia
import Foundation
import QuartzCore
import VideoToolbox

final class AirPlayH264Decoder: @unchecked Sendable {
    weak var delegate: VideoDecoderDelegate?

    private let decoder = VideoDecoder()
    private var formatDescription: CMVideoFormatDescription?
    private var pendingParameterSets = Data()
    private var lastSPS = Data()
    private var lastPPS = Data()
    private var waitingForIDR = true
    private var hasLoggedFirstFrame = false
    private var hasLoggedDecodeSkip = false
    private var hasLoggedWaitingForIDR = false

    init() {
        decoder.delegate = self
    }

    func reset() {
        pendingParameterSets.removeAll(keepingCapacity: false)
        formatDescription = nil
        lastSPS = Data()
        lastPPS = Data()
        waitingForIDR = true
        hasLoggedFirstFrame = false
        hasLoggedDecodeSkip = false
        hasLoggedWaitingForIDR = false
        decoder.invalidateSession()
    }

    func noteStreamSuspended() {
        // Keep decoder state. Screen-off only pauses new IDRs from the client;
        // do not force an IDR wait — after unlock iPhone often continues with P-frames.
        AppLogger.info("Mirror decoder marked suspended", category: .airplay)
    }

    func noteStreamResumed() {
        // Session still valid: resume decoding immediately.
        waitingForIDR = false
        hasLoggedWaitingForIDR = false
        AppLogger.info("Mirror video resumed; continuing decode", category: .airplay)
    }

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

    func ingestParameterSets(_ payload: Data) {
        guard payload.count >= 11 else {
            AppLogger.warning("AirPlay SPS/PPS packet too short (\(payload.count) bytes)", category: .airplay)
            return
        }

        let bytes = [UInt8](payload)
        let spsSize = Int(bytes[6]) << 8 | Int(bytes[7])
        guard spsSize > 0, spsSize + 11 + 2 <= bytes.count else {
            let preview = payload.prefix(min(payload.count, 12)).map { String(format: "%02x", $0) }.joined(separator: " ")
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
                AppLogger.warning("AirPlay H264 decode skipped: no format description yet (\(frameData.count) bytes)", category: .airplay)
            }
            return
        }

        guard let avcc = rebuildAVCC(from: frameData) else {
            return
        }

        let nals = extractNALUnits(from: avcc)
        let hasIDR = nals.contains { (($0.first ?? 0) & 0x1F) == 5 }

        if waitingForIDR, !hasIDR {
            if !hasLoggedWaitingForIDR {
                hasLoggedWaitingForIDR = true
                AppLogger.info("AirPlay H264 skipping frames until IDR (new format)", category: .airplay)
            }
            return
        }

        if hasIDR {
            waitingForIDR = false
            hasLoggedWaitingForIDR = false
        }

        if !hasLoggedFirstFrame {
            let types = nals.map { String(($0.first ?? 0) & 0x1F) }.joined(separator: ",")
            AppLogger.info("AirPlay H264 NAL types in first frame: [\(types)]", category: .airplay)
        }

        guard let sampleBuffer = makeSampleBuffer(fromAVCC: avcc) else {
            AppLogger.warning("AirPlay H264 sample buffer creation failed (\(frameData.count) bytes)", category: .airplay)
            return
        }

        if !hasLoggedFirstFrame {
            hasLoggedFirstFrame = true
            AppLogger.info("AirPlay H264 first frame (\(frameData.count) bytes)", category: .airplay)
        }

        decoder.decode(sampleBuffer: sampleBuffer)
    }

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
        _ = decoder.configure(with: description)
        return true
    }

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
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        delegate?.decoder(decoder, didOutputPixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    func decoder(_ decoder: VideoDecoder, didFailWithError error: Error) {
        delegate?.decoder(decoder, didFailWithError: error)
    }
}
