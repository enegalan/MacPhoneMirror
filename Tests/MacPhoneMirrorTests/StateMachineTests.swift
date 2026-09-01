@testable import MacPhoneMirrorCore
import Combine
import CoreGraphics
import Testing

struct StateMachineTests {
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

    @Test func mirrorSessionOpenCloseCycle() {
        let manager = SessionManager()
        let device = PhoneDevice(
            id: "test-device-1",
            name: "Test iPhone",
            connectionType: .simulated
        )
        let receiver = TestPatternReceiver()
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

    @Test func airPlaySessionReplacementClosesPreviousWindow() {
        let manager = SessionManager()
        let first = PhoneDevice(id: "airplay-A", name: "Phone A", connectionType: .wifi)
        let second = PhoneDevice(id: "airplay-B", name: "Phone B", connectionType: .wifi)
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
}
