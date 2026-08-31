import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreGraphics

public protocol VideoRenderer: AnyObject, Sendable {
    func render(_ frame: VideoFrame)
}

public final class MetalVideoRenderer: NSObject, VideoRenderer, MTKViewDelegate, @unchecked Sendable {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private var currentCVTexture: CVMetalTexture?
    private let renderLock = NSLock()
    private var renderPipelineState: MTLRenderPipelineState?
    private var didLogFirstDraw = false
    
    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device = device,
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        super.init()
        
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache
        
        setupPipeline()
    }
    
    private func setupPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoords;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float4 positions[4] = {
                float4(-1.0, -1.0, 0.0, 1.0),
                float4( 1.0, -1.0, 0.0, 1.0),
                float4(-1.0,  1.0, 0.0, 1.0),
                float4( 1.0,  1.0, 0.0, 1.0)
            };
            float2 texCoords[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };
            VertexOut out;
            out.position = positions[vertexID];
            out.texCoords = texCoords[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]]) {
            constexpr sampler linearSampler(mip_filter::none,
                                            mag_filter::linear,
                                            min_filter::linear,
                                            address::clamp_to_edge);
            return texture.sample(linearSampler, in.texCoords);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            AppLogger.error("Failed to create Metal render pipeline: \(error.localizedDescription)", category: .airplay)
        }
    }
    
    public func render(_ frame: VideoFrame) {
        let start = CFAbsoluteTimeGetCurrent()
        guard let cache = textureCache else { return }
        
        let pixelBuffer = frame.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var metalTextureOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &metalTextureOut
        )
        
        if status == kCVReturnSuccess, let metalTextureOut = metalTextureOut,
           let texture = CVMetalTextureGetTexture(metalTextureOut) {
            renderLock.lock()
            // Keep CVMetalTexture alive; releasing it can invalidate the MTLTexture.
            self.currentCVTexture = metalTextureOut
            self.currentTexture = texture
            renderLock.unlock()
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            PerformanceMonitor.shared.recordRenderTime(elapsed)
            PerformanceMonitor.shared.recordFrameReceived(resolution: CGSize(width: width, height: height))
        } else if status != kCVReturnSuccess {
            AppLogger.warning("CVMetalTextureCacheCreateTextureFromImage failed: \(status)", category: .airplay)
        }
    }
    
    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        renderLock.lock()
        let texture = currentTexture
        renderLock.unlock()
        
        guard let texture = texture,
              let pipelineState = renderPipelineState,
              let currentRenderPassDescriptor = view.currentRenderPassDescriptor,
              let currentDrawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()

        if !didLogFirstDraw {
            didLogFirstDraw = true
            AppLogger.info("Metal draw first frame (\(texture.width)x\(texture.height))", category: .airplay)
        }
    }
}
