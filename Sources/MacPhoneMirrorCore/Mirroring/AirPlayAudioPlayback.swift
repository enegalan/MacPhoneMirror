import AVFoundation
import CommonCrypto
import CryptoKit
import Foundation

// Decrypts/decodes AirPlay AAC RTP and plays via AVAudioEngine.
// Optional: toggled by AppPreferences.enableAudioPlayback so video-only use stays quiet.

final class AirPlayAudioPlayback: @unchecked Sendable {
    struct StreamConfig: Sendable {
        var compressionType: UInt64 = 8 // AAC-ELD for screen mirroring
        var audioFormat: UInt64 = 0
        var sampleRate: Double = 44100
        var samplesPerFrame: UInt64 = 480
        var sharedKey: Data = .init()
        var aesKey: Data = .init()
        var aesIV: Data = .init()
    }

    private static let noDataMarker = Data([0x00, 0x68, 0x34, 0x00])

    private let queue = DispatchQueue(label: "com.macphonemirror.airplay.audio.playback", qos: .userInteractive)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var aacConverter: AVAudioConverter?
    private var compressedFormat: AVAudioFormat?
    private var pcmFormat: AVAudioFormat?
    private var config = StreamConfig()
    private var didLogDecryptFail = false
    private var didLogDecodeFail = false
    private var didLogFirstAudio = false
    private var framesPlayed: UInt64 = 0
    private var lastPlayedSeq: UInt16?

    /// Applies stream crypto/format from RTSP SETUP and rebuilds the audio engine.
    func configure(_ config: StreamConfig) {
        queue.sync { [weak self] in
            guard let self else { return }
            self.config = config
            teardownLocked()
            lastPlayedSeq = nil
            didLogDecryptFail = false
            didLogDecodeFail = false
            didLogFirstAudio = false
            framesPlayed = 0
            guard AppPreferences.enableAudioPlayback else {
                AppLogger.info(
                    "Audio playback configure skipped (disabled) ct=\(config.compressionType)",
                    category: .airplay
                )
                return
            }
            prepareFormatsLocked()
            rebuildEngineLocked()
            AppLogger.info(
                "Audio playback configure ct=\(config.compressionType) sr=\(Int(config.sampleRate)) "
                    + "spf=\(config.samplesPerFrame) shk=\(config.sharedKey.count)B "
                    + "aesKey=\(config.aesKey.count)B aesIV=\(config.aesIV.count)B",
                category: .airplay
            )
        }
    }

    /// Stops playback and clears stream config/crypto state.
    func reset() {
        queue.sync { [weak self] in
            guard let self else { return }
            teardownLocked()
            config = StreamConfig()
            didLogDecryptFail = false
            didLogDecodeFail = false
            didLogFirstAudio = false
            framesPlayed = 0
            lastPlayedSeq = nil
        }
    }

    /// Queues one RTP packet for decrypt/decode when audio playback is enabled.
    func ingestRTPPacket(_ packet: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            guard AppPreferences.enableAudioPlayback else {
                if engine != nil || player != nil {
                    teardownLocked()
                }
                return
            }
            handlePacketLocked(packet)
        }
    }

    /// Decrypts and plays one RTP payload; drops markers, duplicates, and decode failures.
    private func handlePacketLocked(_ packet: Data) {
        guard packet.count >= 12 else { return }
        guard hasCryptoMaterial else { return }

        // Skip AAC-ELD "no data" markers (12-byte header only, or 16 with marker payload).
        if packet.count == 12 {
            return
        }
        if packet.count == 16, packet.suffix(4) == Self.noDataMarker {
            return
        }

        let header = Data(packet.prefix(12))
        let seq = UInt16(header[2]) << 8 | UInt16(header[3])
        let payload = Data(packet.dropFirst(12))
        guard let plaintext = decryptPayload(payload, rtpHeader: header), !plaintext.isEmpty else { return }
        if plaintext == Self.noDataMarker {
            return
        }

        // AAC-ELD retransmit window requires strict forward-only acceptance.
        // Update only after authenticated decrypt so forged packets cannot advance the window.
        if config.compressionType == 8 {
            if let last = lastPlayedSeq {
                let delta = Self.sequenceDelta(seq, from: last)
                if delta <= 0 {
                    return
                }
            }
            lastPlayedSeq = seq
        }

        switch config.compressionType {
        case 1:
            playPCM(plaintext)
        case 2:
            playALAC(plaintext)
        case 4, 8:
            playAAC(plaintext)
        default:
            if !didLogDecodeFail {
                didLogDecodeFail = true
                AppLogger.warning(
                    "Audio unsupported compression type ct=\(config.compressionType)",
                    category: .airplay
                )
            }
        }
    }

    /// Signed RTP sequence distance with 16-bit wrap.
    private static func sequenceDelta(_ seq: UInt16, from previous: UInt16) -> Int {
        var delta = Int(seq) - Int(previous)
        if delta > 32767 {
            delta -= 65536
        }
        if delta < -32768 {
            delta += 65536
        }
        return delta
    }

    private var hasCryptoMaterial: Bool {
        config.sharedKey.count >= 32
            || (config.aesKey.count == 16 && config.aesIV.count == 16)
    }

    /// Chooses ChaCha20-Poly1305 or AES-CBC based on SETUP keys. Never treats plaintext as authenticated.
    private func decryptPayload(_ payload: Data, rtpHeader: Data) -> Data? {
        if config.sharedKey.count >= 32 {
            return decryptChaChaPoly(payload: payload, rtpHeader: rtpHeader)
        }
        if config.aesKey.count == 16, config.aesIV.count == 16, payload.count >= 16 {
            return decryptAESCBC(payload)
        }
        return nil
    }

    /// FairPlay AES-CBC decrypt for screen-mirroring AAC-ELD; nil on CCCrypt failure.
    private func decryptAESCBC(_ payload: Data) -> Data? {
        // UxPlay raop_buffer: CBC decrypt full 16-byte blocks, copy remainder, reset IV each packet.
        let encryptedLength = (payload.count / 16) * 16
        guard encryptedLength > 0 else { return payload }

        var keyBytes = [UInt8](config.aesKey)
        var ivBytes = [UInt8](config.aesIV)
        var inputBytes = [UInt8](payload.prefix(encryptedLength))
        var outputBytes = [UInt8](repeating: 0, count: encryptedLength)
        var outLength: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(0), // no padding — exact block multiples
            &keyBytes,
            keyBytes.count,
            &ivBytes,
            &inputBytes,
            inputBytes.count,
            &outputBytes,
            outputBytes.count,
            &outLength
        )

        guard status == kCCSuccess else {
            if !didLogDecryptFail {
                didLogDecryptFail = true
                AppLogger.warning("Audio AES-CBC decrypt failed status=\(status)", category: .airplay)
            }
            return nil
        }

        var result = Data(outputBytes.prefix(outLength))
        if encryptedLength < payload.count {
            result.append(payload.suffix(from: encryptedLength))
        }
        return result
    }

    /// ChaCha20-Poly1305 open using `shk` and RTP header AAD; nil on auth failure.
    private func decryptChaChaPoly(payload: Data, rtpHeader: Data) -> Data? {
        guard payload.count > 24, config.sharedKey.count >= 32 else { return nil }
        let body = payload.dropLast(24)
        let trailer = payload.suffix(24)
        let tag = Data(trailer.prefix(16))
        let nonceSuffix = Data(trailer.suffix(8))
        var nonce = Data(count: 4)
        nonce.append(nonceSuffix)

        guard rtpHeader.count >= 12 else { return nil }
        let aad = Data(rtpHeader[4 ..< 12])
        let key = SymmetricKey(data: config.sharedKey.prefix(32))

        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaPoly.Nonce(data: nonce),
                ciphertext: body,
                tag: tag
            )
            return try ChaChaPoly.open(box, using: key, authenticating: aad)
        } catch {
            if !didLogDecryptFail {
                didLogDecryptFail = true
                AppLogger.warning("Audio ChaCha20-Poly1305 decrypt failed", category: .airplay)
            }
            return nil
        }
    }

    /// Builds PCM and compressed `AVAudioFormat` / converter for the current `ct`.
    private func prepareFormatsLocked() {
        let rate = config.sampleRate > 0 ? config.sampleRate : 44100
        let framesPerPacket = max(config.samplesPerFrame, 1)

        guard let pcm = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 2,
            interleaved: false
        ) else { return }
        pcmFormat = pcm

        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = rate
        asbd.mChannelsPerFrame = 2
        asbd.mFramesPerPacket = UInt32(framesPerPacket)
        switch config.compressionType {
        case 2:
            asbd.mFormatID = kAudioFormatAppleLossless
            asbd.mFormatFlags = 0
            asbd.mBytesPerPacket = 0
            asbd.mBytesPerFrame = 0
            asbd.mBitsPerChannel = 0
            asbd.mReserved = 0
        case 4:
            asbd.mFormatID = kAudioFormatMPEG4AAC
        case 8:
            asbd.mFormatID = kAudioFormatMPEG4AAC_ELD
        default:
            compressedFormat = nil
            aacConverter = nil
            return
        }

        guard let compressed = AVAudioFormat(streamDescription: &asbd),
              let converter = AVAudioConverter(from: compressed, to: pcm)
        else {
            AppLogger.warning("Audio converter unavailable for ct=\(config.compressionType)", category: .airplay)
            compressedFormat = nil
            aacConverter = nil
            return
        }
        if config.compressionType == 2 {
            let cookie = Self.alacMagicCookie(
                framesPerPacket: UInt32(framesPerPacket),
                sampleRate: UInt32(rate),
                channels: 2,
                bitDepth: 16
            )
            converter.magicCookie = cookie
        }
        compressedFormat = compressed
        aacConverter = converter
    }

    /// ALAC magic cookie layout used by AirPlay / CoreAudio.
    private static func alacMagicCookie(
        framesPerPacket: UInt32,
        sampleRate: UInt32,
        channels: UInt8,
        bitDepth: UInt8
    ) -> Data {
        var cookie = Data(count: 36)
        cookie.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            /// Writes a big-endian UInt32 into the cookie at `offset`.
            func write32(_ value: UInt32, at offset: Int) {
                base[offset] = UInt8((value >> 24) & 0xFF)
                base[offset + 1] = UInt8((value >> 16) & 0xFF)
                base[offset + 2] = UInt8((value >> 8) & 0xFF)
                base[offset + 3] = UInt8(value & 0xFF)
            }
            write32(framesPerPacket, at: 0)
            base[4] = 0
            base[5] = bitDepth
            base[6] = 40
            base[7] = 10
            write32(14, at: 8)
            write32(255, at: 12)
            write32(0, at: 16)
            write32(0, at: 20)
            write32(UInt32(channels), at: 24)
            write32(0, at: 28)
            write32(sampleRate, at: 32)
        }
        return cookie
    }

    /// Creates and starts AVAudioEngine + player node for the current PCM format.
    private func rebuildEngineLocked() {
        guard let pcmFormat else { return }
        teardownEngineOnlyLocked()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: pcmFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outFormat)
        engine.mainMixerNode.outputVolume = 1.0
        do {
            try engine.start()
            player.play()
            self.engine = engine
            self.player = player
        } catch {
            AppLogger.error("Audio engine start failed: \(error.localizedDescription)", category: .airplay)
            teardownEngineOnlyLocked()
        }
    }

    /// Stops and releases the audio engine/player without clearing format converters.
    private func teardownEngineOnlyLocked() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    /// Full teardown: engine plus converter/format state.
    private func teardownLocked() {
        teardownEngineOnlyLocked()
        aacConverter = nil
        compressedFormat = nil
        pcmFormat = nil
    }

    /// Schedules interleaved Int16 stereo PCM as float buffers.
    private func playPCM(_ data: Data) {
        ensureEngine()
        guard let player, let format = pcmFormat else { return }
        let frameCount = data.count / 4
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Int16.self).baseAddress,
                  let left = buffer.floatChannelData?[0],
                  let right = buffer.floatChannelData?[1]
            else { return }
            for i in 0 ..< frameCount {
                left[i] = Float(base[i * 2]) / Float(Int16.max)
                right[i] = Float(base[i * 2 + 1]) / Float(Int16.max)
            }
        }
        schedule(buffer, player: player)
    }

    /// Plays ALAC, or raw PCM when the payload size matches expected frames.
    private func playALAC(_ data: Data) {
        // Some senders still emit raw PCM under ct=2; accept obvious PCM frames.
        let expected = Int(config.samplesPerFrame) * 4
        if expected > 0, data.count == expected || data.count == expected + 3 {
            let pcm = data.count == expected + 3 ? Data(data.dropFirst(3)) : data
            playPCM(pcm)
            return
        }
        playCompressed(data, label: "ALAC")
    }

    /// Decodes and plays AAC / AAC-ELD compressed frames.
    private func playAAC(_ data: Data) {
        playCompressed(data, label: "AAC")
    }

    /// Converts one compressed packet to PCM via `AVAudioConverter` and schedules it.
    private func playCompressed(_ data: Data, label: String) {
        ensureEngine()
        guard let player,
              let converter = aacConverter,
              let compressedFormat,
              let pcmFormat
        else {
            if !didLogDecodeFail {
                didLogDecodeFail = true
                AppLogger.warning("Audio \(label) decode skipped: converter not ready", category: .airplay)
            }
            return
        }

        let maxPacket = max(data.count, 1)
        let compressed = AVAudioCompressedBuffer(
            format: compressedFormat,
            packetCapacity: 1,
            maximumPacketSize: maxPacket
        )

        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            memcpy(compressed.data, src, data.count)
        }
        compressed.byteLength = UInt32(data.count)
        compressed.packetCount = 1
        if let descriptions = compressed.packetDescriptions {
            descriptions[0] = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(data.count)
            )
        }

        let frameCapacity = AVAudioFrameCount(max(config.samplesPerFrame, 480) * 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCapacity) else { return }

        final class InputState: @unchecked Sendable {
            let buffer: AVAudioCompressedBuffer
            var provided = false
            /// Holds the single compressed buffer for the converter pull callback.
            init(_ buffer: AVAudioCompressedBuffer) {
                self.buffer = buffer
            }
        }
        let state = InputState(compressed)

        var error: NSError?
        let status = converter.convert(to: pcmBuffer, error: &error) { _, outStatus in
            if state.provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            state.provided = true
            outStatus.pointee = .haveData
            return state.buffer
        }

        if status == .error || pcmBuffer.frameLength == 0 {
            if !didLogDecodeFail {
                didLogDecodeFail = true
                let message = error?.localizedDescription ?? "empty PCM"
                AppLogger.warning(
                    "Audio \(label) decode failed (\(data.count)B): \(message)",
                    category: .airplay
                )
            }
            return
        }

        schedule(pcmBuffer, player: player)
    }

    /// Lazily rebuilds formats/engine if playback nodes were torn down.
    private func ensureEngine() {
        guard AppPreferences.enableAudioPlayback else {
            teardownEngineOnlyLocked()
            return
        }
        if engine == nil || player == nil {
            if pcmFormat == nil {
                prepareFormatsLocked()
            }
            rebuildEngineLocked()
        }
    }

    /// Enqueues a PCM buffer on the player node and ensures it is playing.
    private func schedule(_ buffer: AVAudioPCMBuffer, player: AVAudioPlayerNode) {
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
        framesPlayed += 1
        if !didLogFirstAudio {
            didLogFirstAudio = true
            AppLogger.info(
                "Audio playback started ct=\(config.compressionType) frames=\(buffer.frameLength)",
                category: .airplay
            )
        }
    }
}
