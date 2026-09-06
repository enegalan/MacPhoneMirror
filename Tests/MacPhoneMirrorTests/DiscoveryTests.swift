@testable import MacPhoneMirrorCore
import Testing

// Unit tests for USB device filter / discovery behavior.

struct DiscoveryTests {
    /// Asserts Bluetooth devices discover wirelessly but do not mirror screens.
    @Test func bluetoothDeviceCanConnectWirelessly() {
        let device = PhoneDevice(
            name: "My iPhone",
            connectionType: .bluetooth
        )
        #expect(device.supportsWirelessDiscovery)
        #expect(device.canConnect)
        #expect(!device.supportsScreenMirroring)
    }

    /// Asserts available USB devices support screen mirroring and can connect.
    @Test func usbDeviceSupportsScreenMirroring() {
        let device = PhoneDevice(
            name: "My iPhone",
            connectionType: .usb,
            isAvailable: true
        )
        #expect(device.supportsScreenMirroring)
        #expect(device.canConnect)
    }
}
