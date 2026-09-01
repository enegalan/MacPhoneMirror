@testable import MacPhoneMirrorCore
import CoreGraphics
import Testing

struct DeviceModelTests {
    @Test func iPhone16ProSpecifications() {
        let model = PhoneModel.iPhone16Pro
        #expect(model.pointSize == CGSize(width: 402, height: 874))
        #expect(model.cutoutStyle == .dynamicIsland)
        #expect(model.scaleFactor == 3.0)
        #expect(model.pixelSize == CGSize(width: 1206, height: 2622))
        #expect(model.screenCornerRadius == 56.0)
        #expect(model.topSafeAreaInset > 50.0)
    }

    @Test func iPhone13NotchSpecifications() {
        let model = PhoneModel.iPhone13
        #expect(model.cutoutStyle == .notch)
        #expect(model.pointSize == CGSize(width: 390, height: 844))
        #expect(model.screenCornerRadius == 47.0)
    }

    @Test func iPhoneSE3Specifications() {
        let model = PhoneModel.iPhoneSE3
        #expect(model.cutoutStyle == .none)
        #expect(model.scaleFactor == 2.0)
        #expect(model.screenCornerRadius == 0.0)
    }
}
