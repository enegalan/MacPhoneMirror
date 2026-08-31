import SwiftUI
import MetalKit
import CoreVideo
import MacPhoneMirrorCore
import Combine

public struct MetalVideoView: NSViewRepresentable {
    @ObservedObject var stateHolder: MetalViewStateHolder

    public init(stateHolder: MetalViewStateHolder) {
        self.stateHolder = stateHolder
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = stateHolder.renderer?.device ?? MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.delegate = stateHolder.renderer
        // Continuous display loop (do not require setNeedsDisplay).
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.framebufferOnly = false
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        if nsView.delegate !== stateHolder.renderer {
            nsView.delegate = stateHolder.renderer
        }
        nsView.isPaused = false
        nsView.enableSetNeedsDisplay = false
    }
}

public final class MetalViewStateHolder: ObservableObject, @unchecked Sendable {
    public let renderer: MetalVideoRenderer?
    private var cancellables = Set<AnyCancellable>()
    private var didLogFirstRender = false

    public init(renderer: MetalVideoRenderer? = MetalVideoRenderer()) {
        self.renderer = renderer
        if renderer == nil {
            AppLogger.error("MetalVideoRenderer failed to initialize", category: .airplay)
        }
        if let session = SessionManager.shared.currentReceiver {
            bind(to: session)
        }
    }

    public func bind(to receiver: ScreenMirrorReceiver) {
        cancellables.removeAll()
        didLogFirstRender = false
        receiver.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                self.renderer?.render(frame)
                if !self.didLogFirstRender {
                    self.didLogFirstRender = true
                    AppLogger.info(
                        "Metal UI received frame (\(frame.width)x\(frame.height))",
                        category: .airplay
                    )
                }
            }
            .store(in: &cancellables)

        if let networkReceiver = receiver as? NetworkStreamReceiver,
           let latestFrame = networkReceiver.latestVideoFrame() {
            DispatchQueue.main.async { [weak self] in
                self?.renderer?.render(latestFrame)
            }
        }
    }
}
