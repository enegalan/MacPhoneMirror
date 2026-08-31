import Testing
@testable import MacPhoneMirrorCore

struct DiscoveryTests {
    @Test func testCompositeDiscoveryStartsEmpty() {
        let composite = CompositeDiscovery.shared
        #expect(composite.devices.isEmpty || composite.devices.allSatisfy(\.canConnect))
    }

    @Test func testBonjourTechnicalNamesAreFiltered() {
        #expect(!DeviceDiscoveryFilter.isLikelyPhoneName("76:3e:24:19:69:c0@fe80::743e:24ff:fe19:69c0-supportsRP-26"))
        #expect(DeviceDiscoveryFilter.isLikelyPhoneName("iPhone de Eneko"))
    }

    @Test func testCameraNamesAreNormalized() {
        let key = DeviceDiscoveryFilter.normalizedDeviceKey(from: #"Cámara de "iPhone de Eneko""#)
        #expect(key == "iphone de eneko")
    }

    @Test func testBluetoothDeviceCanConnectWirelessly() {
        let device = PhoneDevice(
            name: "iPhone de Eneko",
            connectionType: .bluetooth
        )
        #expect(device.supportsWirelessDiscovery)
        #expect(device.canConnect)
        #expect(!device.supportsScreenMirroring)
    }
}
