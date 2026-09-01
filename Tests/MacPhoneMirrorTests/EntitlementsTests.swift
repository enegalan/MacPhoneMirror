import Testing
@testable import MacPhoneMirrorCore

struct EntitlementsTests {
    @Test func testAllFeaturesAreAvailable() {
        for feature in Feature.allCases {
            let _ = feature.description
        }
        #expect(Feature.allCases.count == 9)
    }

    @Test func testFeatureDescriptions() {
        #expect(!Feature.screenMirroring.description.isEmpty)
        #expect(!Feature.advancedControl.description.isEmpty)
        #expect(!Feature.customFrames.description.isEmpty)
    }
}
