@testable import MacPhoneMirrorCore
import CoreGraphics
import Testing

// Unit tests for PhoneModel sizes and DeviceOrientation helpers.

struct DeviceModelTests {
    /// Asserts iPhone 16 Pro point/pixel sizes and safe-area insets.
    @Test func iPhone16ProSpecifications() {
        let model = PhoneModel.iPhone16Pro
        #expect(model.pointSize == CGSize(width: 402, height: 874))
        #expect(model.scaleFactor == 3.0)
        #expect(model.pixelSize == CGSize(width: 1206, height: 2622))
        #expect(model.screenCornerRadius == 56.0)
        #expect(model.topSafeAreaInset > 50.0)
    }

    /// Asserts iPhone 13 point size, corner radius, and top inset.
    @Test func iPhone13Specifications() {
        let model = PhoneModel.iPhone13
        #expect(model.pointSize == CGSize(width: 390, height: 844))
        #expect(model.screenCornerRadius == 47.0)
        #expect(model.topSafeAreaInset == 47.0)
    }

    /// Asserts iPhone SE 3 scale factor and zero corner/bottom insets.
    @Test func iPhoneSE3Specifications() {
        let model = PhoneModel.iPhoneSE3
        #expect(model.scaleFactor == 2.0)
        #expect(model.screenCornerRadius == 0.0)
        #expect(model.bottomSafeAreaInset == 0.0)
    }
}
