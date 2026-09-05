import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Foundation

public final class AVFoundationUSBReceiver: NSObject, ScreenMirrorReceiver,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable
{
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameSubject = PassthroughSubject<VideoFrame, Never>()
    private let sessionQueue = DispatchQueue(label: "com.macphonemirror.usb.session", qos: .userInteractive)
    private let videoQueue = DispatchQueue(label: "com.macphonemirror.usb.video", qos: .userInteractive)
    private let lock = NSLock()

    private var _state: ReceiverState = .idle
    private var frameCounter: UInt64 = 0
    private var targetDeviceID: String?

    public var state: ReceiverState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var framePublisher: AnyPublisher<VideoFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public init(deviceID: String? = nil) {
        targetDeviceID = deviceID
        super.init()
    }

    private func setState(_ newState: ReceiverState) {
        lock.lock()
        _state = newState
        lock.unlock()
    }

    private func usbPreset() -> AVCaptureSession.Preset {
        switch StreamConfiguration.shared.quality {
        case .ultra, .high:
            .high
        case .balanced, .lowBandwidth:
            .medium
        }
    }

    public func start() async throws {
        setState(.starting)

        AppLogger.info("Starting AVFoundation USB Mirror Receiver...", category: .video)

        // Find capture device for iPhone screen mirroring over USB
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discoverySession.devices.filter { DeviceDiscoveryFilter.isUSBPhoneScreenDevice($0) }
        let chosenDevice: AVCaptureDevice? = if let targetID = targetDeviceID {
            devices.first { $0.uniqueID == targetID }
        } else {
            devices.first
        }

        guard let device = chosenDevice else {
            setState(.failed("No compatible iPhone screen capture device found."))
            AppLogger.warning("No USB capture device found", category: .video)
            throw NSError(
                domain: AppInfo.name,
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No compatible iPhone USB capture device found."]
            )
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.configureAndStartSession(device: device, continuation: continuation)
            }
        }
    }

    private func configureAndStartSession(
        device: AVCaptureDevice,
        continuation: CheckedContinuation<Void, Error>
    ) {
        do {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = usbPreset()

            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            captureSession.commitConfiguration()
            captureSession.startRunning()

            lock.lock()
            _state = .running
            lock.unlock()

            AppLogger.info(
                "AVFoundation USB Receiver running for device: \(device.localizedName)",
                category: .video
            )
            continuation.resume()
        } catch {
            lock.lock()
            _state = .failed(error.localizedDescription)
            lock.unlock()
            continuation.resume(throwing: error)
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            lock.lock()
            _state = .stopped
            lock.unlock()
            AppLogger.info("AVFoundation USB Receiver stopped", category: .video)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        frameCounter += 1
        let currentCount = frameCounter
        lock.unlock()

        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimestamp: pts,
            orientation: .portrait,
            frameIndex: currentCount,
            captureTimestamp: .now()
        )

        frameSubject.send(frame)
    }

    public func captureOutput(_: AVCaptureOutput, didDrop _: CMSampleBuffer, from _: AVCaptureConnection) {
        PerformanceMonitor.shared.recordDroppedFrame()
    }
}
