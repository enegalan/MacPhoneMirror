@testable import MacPhoneMirrorCore
import Foundation
import Testing

// Cancellation cleanup for HID gesture helpers that sleep between press/release reports.

struct BluetoothHIDGestureTests {
    @Test func clickLeftCancellationReleasesButton() async {
        let transport = BluetoothHIDTransport.shared
        _ = transport.setButton(.left, pressed: false)

        let task = Task {
            try await transport.clickLeft()
        }
        task.cancel()
        _ = try? await task.value

        #expect(transport.getActiveButtons() == 0)
    }

    @Test func performDragCancellationReleasesButton() async {
        let transport = BluetoothHIDTransport.shared
        _ = transport.setButton(.left, pressed: false)

        let task = Task {
            try await transport.performDrag(
                from: (0.2, 0.2),
                to: (0.8, 0.8),
                steps: 8,
                stepDelayNs: 50_000_000,
                holdAtEndNs: 50_000_000
            )
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
        task.cancel()
        _ = try? await task.value

        #expect(transport.getActiveButtons() == 0)
    }

    @Test func sendKeyChordCancellationReleasesKeys() async {
        let transport = BluetoothHIDTransport.shared
        transport.transmitKeyboardReport(HIDKeyboardReport(modifiers: 0, keyCodes: []))

        let task = Task {
            try await transport.sendKeyChord(modifiers: 0x01, keyCode: 0x04)
        }
        task.cancel()
        _ = try? await task.value

        #expect(transport.cachedKeyboard == Data([0, 0, 0, 0, 0, 0, 0, 0]))
    }

    @Test func sendConsumerPulseCancellationReleasesUsage() async {
        let transport = BluetoothHIDTransport.shared
        transport.transmitConsumerReport(0)

        let task = Task {
            try await transport.sendConsumerPulse(.power)
        }
        task.cancel()
        _ = try? await task.value

        #expect(transport.cachedConsumer == Data([0, 0]))
    }
}
