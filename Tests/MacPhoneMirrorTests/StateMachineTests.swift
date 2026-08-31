import Testing
import CoreGraphics
@testable import MacPhoneMirrorCore

struct StateMachineTests {
    @Test func testConnectionStateTransitions() {
        var state = ConnectionState.disconnected
        #expect(!state.isConnectedOrMirroring)
        #expect(state.activeDevice == nil)
        
        let device = PhoneDevice.mockDevice
        state = .connecting(device)
        #expect(state.activeDevice?.id == device.id)
        #expect(!state.isConnectedOrMirroring)
        
        state = .mirroring(device)
        #expect(state.isConnectedOrMirroring)
        #expect(state.activeDevice?.id == device.id)
        
        state = .disconnected
        #expect(!state.isConnectedOrMirroring)
    }
    
    @Test func testDeviceOrientationHelpers() {
        let portrait = DeviceOrientation.portrait
        #expect(portrait.isPortrait)
        #expect(!portrait.isLandscape)
        #expect(portrait.rotationDegrees == 0.0)
        
        let landscape = DeviceOrientation.landscapeRight
        #expect(landscape.isLandscape)
        #expect(!landscape.isPortrait)
        #expect(landscape.rotationDegrees == -90.0)
        
        let baseSize = CGSize(width: 393, height: 852)
        let oriented = landscape.orientedSize(for: baseSize)
        #expect(oriented.width == 852)
        #expect(oriented.height == 393)
    }
}
