import Testing
import CoreGraphics
@testable import MacPhoneMirrorCore

struct CoordinateMappingTests {
    let mapper = StandardCoordinateMapper()
    let device = PhoneDevice.mockDevice
    
    @Test func testPortraitCenterMapping() {
        let viewport = CGSize(width: 400, height: 800)
        let centerPoint = CGPoint(x: 200, y: 400)
        let mapped = mapper.map(point: centerPoint, in: viewport, device: device, orientation: .portrait)
        
        #expect(mapped != nil)
        if let mapped = mapped {
            #expect(abs(mapped.x - 0.5) < 0.01)
            #expect(abs(mapped.y - 0.5) < 0.01)
        }
    }
    
    @Test func testLandscapeMapping() {
        let viewport = CGSize(width: 800, height: 400)
        let centerPoint = CGPoint(x: 400, y: 200)
        let mapped = mapper.map(point: centerPoint, in: viewport, device: device, orientation: .landscapeRight)
        
        #expect(mapped != nil)
        if let mapped = mapped {
            #expect(abs(mapped.x - 0.5) < 0.01)
            #expect(abs(mapped.y - 0.5) < 0.01)
        }
    }
    
    @Test func testOutsideViewportReturnsNil() {
        let viewport = CGSize(width: 1000, height: 400)
        let outPoint = CGPoint(x: 10, y: 200)
        let mapped = mapper.map(point: outPoint, in: viewport, device: device, orientation: .portrait)
        
        #expect(mapped == nil)
    }
    
    @Test func testNativeResolutionMapping() {
        let viewport = CGSize(width: 393, height: 852)
        let center = CGPoint(x: 393 / 2.0, y: 852 / 2.0)
        let native = mapper.mapToNativeResolution(point: center, in: viewport, device: device, orientation: .portrait)
        
        #expect(native != nil)
        if let native = native {
            let pixelSize = device.model.pixelSize
            #expect(abs(native.x - (pixelSize.width / 2.0)) < 1.0)
            #expect(abs(native.y - (pixelSize.height / 2.0)) < 1.0)
        }
    }
}
