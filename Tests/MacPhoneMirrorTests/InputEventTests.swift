@testable import MacPhoneMirrorCore
import Foundation
import Testing

struct InputEventTests {
    @Test func mouseReportSerialization() {
        let report = HIDMouseReport(buttons: MouseButton.left.rawValue, x: 0x1234, y: 0x5678, wheel: 1)
        let data = report.rawData

        #expect(data.count == 6)
        #expect(data[0] == 1)
        #expect(data[1] == 0x34)
        #expect(data[2] == 0x12)
        #expect(data[3] == 0x78)
        #expect(data[4] == 0x56)
        #expect(Int8(bitPattern: data[5]) == 1)
    }

    @Test func mouseReportFromNormalized() {
        let center = HIDMouseReport.fromNormalized(buttons: 0, normalizedX: 0.5, normalizedY: 0.5)
        #expect(abs(Int(center.x) - Int(HIDMouseReport.axisMax) / 2) <= 1)
        #expect(abs(Int(center.y) - Int(HIDMouseReport.axisMax) / 2) <= 1)

        let corner = HIDMouseReport.fromNormalized(buttons: 0, normalizedX: 1, normalizedY: 0)
        #expect(corner.x == HIDMouseReport.axisMax)
        #expect(corner.y == 0)
    }

    @Test func keyboardReportSerialization() {
        let report = HIDKeyboardReport(modifiers: KeyModifier.leftGUI.rawValue, keyCodes: [0x0B])
        let data = report.rawData

        #expect(data.count == 8) // 1 modifier + 1 reserved + 6 keycodes
        #expect(data[0] == KeyModifier.leftGUI.rawValue)
        #expect(data[1] == 0)
        #expect(data[2] == 0x0B)
    }

    @Test func simulatedInputTransport() async throws {
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
