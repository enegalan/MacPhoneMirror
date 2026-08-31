import Testing
import Foundation
@testable import MacPhoneMirrorCore

struct InputEventTests {
    @Test func testMouseReportSerialization() {
        let report = HIDMouseReport(buttons: MouseButton.left.rawValue, deltaX: 12, deltaY: -8, wheel: 1)
        let data = report.rawData
        
        #expect(data.count == 4)
        #expect(data[0] == 1)
        #expect(data[1] == 12)
        #expect(Int8(bitPattern: data[2]) == -8)
        #expect(data[3] == 1)
    }
    
    @Test func testKeyboardReportSerialization() {
        let report = HIDKeyboardReport(modifiers: KeyModifier.leftGUI.rawValue, keyCodes: [0x0B])
        let data = report.rawData
        
        #expect(data.count == 8) // 1 modifier + 1 reserved + 6 keycodes
        #expect(data[0] == KeyModifier.leftGUI.rawValue)
        #expect(data[1] == 0)
        #expect(data[2] == 0x0B)
    }
    
    @Test func testSimulatedInputTransport() async throws {
        let transport = SimulatedInputTransport()
        #expect(transport.isConnected)
        
        try await transport.send(.homeButton)
        #expect(transport.sentEventsCount == 1)
        #expect(transport.lastEvent == .homeButton)
        
        try await transport.send(.pointerDown(button: .left))
        #expect(transport.sentEventsCount == 2)
        #expect(transport.lastEvent == .pointerDown(button: .left))
    }
}
