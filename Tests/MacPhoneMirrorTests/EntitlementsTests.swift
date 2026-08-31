import Testing
@testable import MacPhoneMirrorCore

struct EntitlementsTests {
    @Test func testFeatureProGating() {
        let freeFeature = Feature.screenMirroring
        #expect(!freeFeature.isProOnly)
        
        let proFeature = Feature.advancedControl
        #expect(proFeature.isProOnly)
        
        let provider = LocalEntitlementProvider()
        provider.setProStatusDirectly(false)
        #expect(provider.isEnabled(freeFeature))
        #expect(!provider.isEnabled(proFeature))
        
        provider.setProStatusDirectly(true)
        #expect(provider.isEnabled(proFeature))
    }
    
    @Test func testUnlockProWithLicenseKey() async {
        let provider = LocalEntitlementProvider()
        provider.setProStatusDirectly(false)
        
        let failed = await provider.unlockPro(licenseKey: "   ")
        #expect(!failed)
        #expect(!provider.isProUser)
        
        let success = await provider.unlockPro(licenseKey: "MPM-PRO-LICENSE-VALID")
        #expect(success)
        #expect(provider.isProUser)
    }
}
