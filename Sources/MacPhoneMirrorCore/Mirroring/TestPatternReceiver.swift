import AppKit
import Combine
import CoreGraphics
import CoreVideo
import Foundation

public final class TestPatternReceiver: ScreenMirrorReceiver, @unchecked Sendable {
    private let frameSubject = PassthroughSubject<VideoFrame, Never>()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.macphonemirror.testpattern", qos: .userInteractive)
    private let lock = NSLock()

    private var _state: ReceiverState = .idle
    private var frameCounter: UInt64 = 0
    private var currentOrientation: DeviceOrientation = .portrait
    private var pixelBufferPool: CVPixelBufferPool?

    // Interactive state
    public var touchPoints: [CGPoint] = []
    public var activeAppName: String = "SpringBoard"

    public var state: ReceiverState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var framePublisher: AnyPublisher<VideoFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public init() {
        createPixelBufferPool(width: 1179, height: 2556)
    }

    private func createPixelBufferPool(width: Int, height: Int) {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 10,
        ]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
    }

    public func setOrientation(_ orientation: DeviceOrientation) {
        lock.lock()
        currentOrientation = orientation
        lock.unlock()
    }

    public func addTouchRipple(at normalizedPoint: CGPoint) {
        lock.lock()
        touchPoints.append(normalizedPoint)
        if touchPoints.count > 5 {
            touchPoints.removeFirst()
        }
        lock.unlock()
    }

    private func setRunningState() {
        lock.lock()
        _state = .running
        lock.unlock()
    }

    public func start() async throws {
        setRunningState()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 60 FPS = ~16.666 ms
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.generateAndEmitFrame()
        }
        self.timer = timer
        timer.resume()

        AppLogger.info("TestPatternReceiver started at 60 FPS", category: .video)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        lock.lock()
        _state = .stopped
        lock.unlock()
        AppLogger.info("TestPatternReceiver stopped", category: .video)
    }

    private func generateAndEmitFrame() {
        guard let pool = pixelBufferPool else { return }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return }

        lock.lock()
        frameCounter += 1
        let count = frameCounter
        let orientation = currentOrientation
        let ripples = touchPoints
        lock.unlock()

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Draw Simulated iOS UI
        drawSimulatediOSUI(in: context, width: width, height: height, frameIndex: count, ripples: ripples)

        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimestamp: .invalid,
            orientation: orientation,
            frameIndex: count,
            captureTimestamp: .now()
        )

        PerformanceMonitor.shared.recordFrameReceived(resolution: CGSize(width: width, height: height))
        frameSubject.send(frame)
    }

    private func drawSimulatediOSUI(in context: CGContext, width: Int, height: Int, frameIndex: UInt64, ripples: [CGPoint]) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        // Dynamic wallpaper gradient
        let timeOffset = Double(frameIndex) * 0.015
        let hue1 = CGFloat((sin(timeOffset) + 1.0) / 2.0)
        let hue2 = CGFloat((cos(timeOffset * 0.7) + 1.0) / 2.0)

        let color1 = NSColor(calibratedHue: 0.6 + (hue1 * 0.1), saturation: 0.75, brightness: 0.35, alpha: 1.0).cgColor
        let color2 = NSColor(calibratedHue: 0.75 + (hue2 * 0.15), saturation: 0.65, brightness: 0.15, alpha: 1.0).cgColor

        let colors = [color1, color2] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: h), options: [])
        }

        // Draw Status Bar Clock
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        let timeString = formatter.string(from: Date())

        let textFont = NSFont.systemFont(ofSize: 52, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.white,
        ]

        let str = NSAttributedString(string: timeString, attributes: textAttributes)
        let line = CTLineCreateWithAttributedString(str)
        context.textPosition = CGPoint(x: 100, y: h - 140)
        CTLineDraw(line, context)

        // Draw Battery Icon & Wi-Fi in Status Bar
        context.setFillColor(NSColor.white.cgColor)
        let batteryRect = CGRect(x: w - 180, y: h - 145, width: 80, height: 38)
        let batteryPath = CGPath(roundedRect: batteryRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(batteryPath)
        context.setLineWidth(3)
        context.strokePath()

        let fillWidth = 60.0
        let fillRect = CGRect(x: w - 176, y: h - 141, width: fillWidth, height: 30)
        context.fill(CGRect(x: w - 97, y: h - 134, width: 5, height: 16)) // battery nub
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(fillRect)

        // Draw App Grid (4x6 icons)
        let cols = 4
        let rows = 6
        let iconSize: CGFloat = 160
        let spacingX = (w - (CGFloat(cols) * iconSize)) / CGFloat(cols + 1)
        let startY = h - 420

        let appColors: [NSColor] = [
            .systemBlue, .systemGreen, .systemOrange, .systemRed,
            .systemPurple, .systemYellow, .systemTeal, .systemPink,
            .systemIndigo, .systemBrown, .systemCyan, .systemMint,
            .systemBlue, .systemGreen, .systemOrange, .systemRed,
            .systemPurple, .systemYellow, .systemTeal, .systemPink,
            .systemIndigo, .systemBrown, .systemCyan, .systemMint,
        ]

        let appNames = [
            "Messages", "Calendar", "Photos", "Camera",
            "Mail", "Clock", "Maps", "Weather",
            "Reminders", "Notes", "Stocks", "Books",
            "App Store", "Podcasts", "TV", "Health",
            "Wallet", "Settings", "Music", "Safari",
            "Files", "Fitness", "Shortcuts", "Terminal",
        ]

        for r in 0 ..< rows {
            for c in 0 ..< cols {
                let index = (r * cols) + c
                let x = spacingX + CGFloat(c) * (iconSize + spacingX)
                let y = startY - CGFloat(r) * (iconSize + 70)

                let iconRect = CGRect(x: x, y: y, width: iconSize, height: iconSize)
                let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 38, cornerHeight: 38, transform: nil)

                context.setFillColor(appColors[index % appColors.count].cgColor)
                context.addPath(iconPath)
                context.fillPath()

                // App Name label
                let nameFont = NSFont.systemFont(ofSize: 26, weight: .medium)
                let nameAttr: [NSAttributedString.Key: Any] = [
                    .font: nameFont,
                    .foregroundColor: NSColor.white,
                ]
                let nameStr = NSAttributedString(string: appNames[index % appNames.count], attributes: nameAttr)
                let nameLine = CTLineCreateWithAttributedString(nameStr)
                let textBounds = CTLineGetBoundsWithOptions(nameLine, [])
                let textX = x + (iconSize - textBounds.width) / 2.0
                context.textPosition = CGPoint(x: textX, y: y - 35)
                CTLineDraw(nameLine, context)
            }
        }

        // Draw Dock
        let dockHeight: CGFloat = 240
        let dockY: CGFloat = 80
        let dockRect = CGRect(x: 40, y: dockY, width: w - 80, height: dockHeight)
        let dockPath = CGPath(roundedRect: dockRect, cornerWidth: 60, cornerHeight: 60, transform: nil)
        context.setFillColor(NSColor(white: 1.0, alpha: 0.22).cgColor)
        context.addPath(dockPath)
        context.fillPath()

        // Draw Home Bar
        let homeBarRect = CGRect(x: (w - 420) / 2.0, y: 30, width: 420, height: 14)
        let homeBarPath = CGPath(roundedRect: homeBarRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(homeBarPath)
        context.fillPath()

        // Draw Touch Ripples
        for point in ripples {
            let px = point.x * w
            let py = (1.0 - point.y) * h // Invert Y for CGContext
            context.setFillColor(NSColor(white: 1.0, alpha: 0.4).cgColor)
            context.fillEllipse(in: CGRect(x: px - 40, y: py - 40, width: 80, height: 80))
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: CGRect(x: px - 60, y: py - 60, width: 120, height: 120))
        }
    }
}
