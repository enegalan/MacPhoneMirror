@testable import MacPhoneMirrorCore
import Testing

struct EntitlementsTests {
    @Test func allFeaturesAreAvailable() {
        for feature in Feature.allCases {
            _ = feature.description
        }
        #expect(Feature.allCases.count == 9)
    }

    @Test func featureDescriptions() {
        #expect(!Feature.screenMirroring.description.isEmpty)
        #expect(!Feature.advancedControl.description.isEmpty)
        #expect(!Feature.customFrames.description.isEmpty)
    }
}
