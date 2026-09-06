@testable import MacPhoneMirrorCore
import CoreGraphics
import Testing

// Unit tests for viewport→phone mapping and letterbox rejection.

struct CoordinateMappingTests {
    let mapper = StandardCoordinateMapper()
    let device = PhoneDevice.mockDevice

    /// Asserts portrait viewport center maps to normalized (0.5, 0.5).
    @Test func portraitCenterMapping() {
        let viewport = CGSize(width: 400, height: 800)
        let centerPoint = CGPoint(x: 200, y: 400)
        let mapped = mapper.map(point: centerPoint, in: viewport, device: device, orientation: .portrait)

        #expect(mapped != nil)
        if let mapped {
            #expect(abs(mapped.x - 0.5) < 0.01)
            #expect(abs(mapped.y - 0.5) < 0.01)
        }
    }

    /// Asserts landscape-right center maps to normalized (0.5, 0.5).
    @Test func landscapeMapping() {
        let viewport = CGSize(width: 800, height: 400)
        let centerPoint = CGPoint(x: 400, y: 200)
        let mapped = mapper.map(point: centerPoint, in: viewport, device: device, orientation: .landscapeRight)

        #expect(mapped != nil)
        if let mapped {
            #expect(abs(mapped.x - 0.5) < 0.01)
            #expect(abs(mapped.y - 0.5) < 0.01)
        }
    }

    /// Asserts points outside the letterboxed phone area return nil.
    @Test func outsideViewportReturnsNil() {
        let viewport = CGSize(width: 1000, height: 400)
        let outPoint = CGPoint(x: 10, y: 200)
        let mapped = mapper.map(point: outPoint, in: viewport, device: device, orientation: .portrait)

        #expect(mapped == nil)
    }

    /// Asserts native-pixel mapping hits the device pixel-size center.
    @Test func nativeResolutionMapping() {
        let viewport = CGSize(width: 393, height: 852)
        let center = CGPoint(x: 393 / 2.0, y: 852 / 2.0)
        let native = mapper.mapToNativeResolution(point: center, in: viewport, device: device, orientation: .portrait)

        #expect(native != nil)
        if let native {
            let pixelSize = device.model.pixelSize
            #expect(abs(native.x - (pixelSize.width / 2.0)) < 1.0)
            #expect(abs(native.y - (pixelSize.height / 2.0)) < 1.0)
        }
    }
}
