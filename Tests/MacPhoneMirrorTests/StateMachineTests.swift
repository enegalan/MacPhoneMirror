@testable import MacPhoneMirrorCore
import Combine
import CoreGraphics
import Testing

// Unit tests for SessionManager/store behavior using SimulatedInputTransport.

struct StateMachineTests {
    /// Asserts ConnectionState helpers track device and connected/mirroring flags.
    @Test func connectionStateTransitions() {
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

    /// Asserts portrait/landscape helpers and orientedSize swap dimensions.
    @Test func deviceOrientationHelpers() {
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

    /// Asserts begin/disconnect publishes open/close and clears session maps.
    @Test func mirrorSessionOpenCloseCycle() {
        let manager = SessionManager()
        let device = PhoneDevice(
            name: "Test iPhone",
            id: "test-device-1",
            connectionType: .simulated
        )
        let receiver = StubScreenMirrorReceiver()
        let transport = SimulatedInputTransport()

        var opened: [String] = []
        var closed: [String] = []
        var cancellables = Set<AnyCancellable>()

        manager.sessionWindowOpenPublisher
            .sink { opened.append($0) }
            .store(in: &cancellables)
        manager.sessionWindowClosePublisher
            .sink { closed.append($0) }
            .store(in: &cancellables)

        let sessionID = manager.beginMirroringSession(
            device: device,
            receiver: receiver,
            transport: transport,
            replaceExistingAirPlay: false
        )

        #expect(sessionID == device.id)
        #expect(manager.session(id: sessionID)?.device.name == "Test iPhone")
        #expect(manager.receiver(for: sessionID) === receiver)
        #expect(manager.hasActiveSessions)
        #expect(opened == [sessionID])

        manager.setOrientation(.landscapeLeft, sessionID: sessionID)
        #expect(manager.session(id: sessionID)?.orientation == .landscapeLeft)

        manager.disconnect(sessionID: sessionID)
        #expect(manager.session(id: sessionID) == nil)
        #expect(!manager.hasActiveSessions)
        #expect(closed == [sessionID])
    }

    /// Asserts a new AirPlay session replaces the previous and closes its window.
    @Test func airPlaySessionReplacementClosesPreviousWindow() {
        let manager = SessionManager()
        let first = PhoneDevice(name: "Phone A", id: "airplay-A", connectionType: .wifi)
        let second = PhoneDevice(name: "Phone B", id: "airplay-B", connectionType: .wifi)
        let receiver = NetworkStreamReceiver.shared
        let transportA = SimulatedInputTransport()
        let transportB = SimulatedInputTransport()

        var closed: [String] = []
        var cancellables = Set<AnyCancellable>()
        manager.sessionWindowClosePublisher
            .sink { closed.append($0) }
            .store(in: &cancellables)

        manager.beginMirroringSession(device: first, receiver: receiver, transport: transportA)
        manager.beginMirroringSession(device: second, receiver: receiver, transport: transportB)

        #expect(manager.session(id: first.id) == nil)
        #expect(manager.session(id: second.id) != nil)
        #expect(closed.contains(first.id))
    }

    /// Asserts disconnect clears all sessions and settles to discovering/disconnected.
    @Test func disconnectClearsSessionMapsAndLeavesDiscovering() async {
        let manager = SessionManager()
        let usb = PhoneDevice(name: "USB Phone", id: "usb-1", connectionType: .usb)
        let wifi = PhoneDevice(name: "WiFi Phone", id: "wifi-1", connectionType: .wifi)

        manager.beginMirroringSession(
            device: usb,
            receiver: StubScreenMirrorReceiver(),
            transport: SimulatedInputTransport(),
            replaceExistingAirPlay: false
        )
        manager.beginMirroringSession(
            device: wifi,
            receiver: StubScreenMirrorReceiver(),
            transport: SimulatedInputTransport(),
            replaceExistingAirPlay: false
        )

        #expect(manager.hasActiveSessions)
        manager.disconnect()
        #expect(!manager.hasActiveSessions)
        #expect(manager.session(id: usb.id) == nil)
        #expect(manager.session(id: wifi.id) == nil)
        #expect(manager.receiver(for: usb.id) == nil)

        for _ in 0 ..< 50 {
            if manager.state == .discovering || manager.state == .disconnected {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Unexpected state after disconnect: \(manager.state)")
    }

    /// Asserts rapid enable/disable leaves the AirPlay service disabled.
    @Test func rapidServiceToggleLeavesServiceDisabled() async {
        let manager = SessionManager()
        manager.setServiceEnabled(true)
        manager.setServiceEnabled(false)
        #expect(!manager.isServiceEnabled)

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!manager.isServiceEnabled)
        switch manager.state {
        case .disconnected, .discovering, .failed:
            break
        default:
            Issue.record("Unexpected state after disable: \(manager.state)")
        }
    }
}
