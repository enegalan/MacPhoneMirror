import Foundation

// Turns PhoneInputEvent-level moves/buttons/swipes into HID mouse/consumer reports.
// Keeps absolute AssistiveTouch coordinates and relative deltas out of the transport core.

extension BluetoothHIDTransport {
    // MARK: - Pointer helpers

    /// Moves AssistiveTouch to an absolute normalized position and updates lastAbsX/Y.
    func movePointerAbsolute(normalizedX: Double, normalizedY: Double) {
        let report = HIDMouseReport.fromNormalized(
            buttons: getActiveButtons(),
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )
        lock.lock()
        lastAbsX = report.x
        lastAbsY = report.y
        lock.unlock()
        transmitMouseReport(report)
    }

    /// Applies a relative delta (scaled by mouse sensitivity) onto the last absolute position.
    func applyRelativeMove(dx: Double, dy: Double, wheel: Int8) {
        lock.lock()
        let nextX = min(max(Int(lastAbsX) + Int((dx * relativeMoveScale).rounded()), 0), Int(HIDMouseReport.axisMax))
        let nextY = min(max(Int(lastAbsY) + Int((dy * relativeMoveScale).rounded()), 0), Int(HIDMouseReport.axisMax))
        lastAbsX = UInt16(nextX)
        lastAbsY = UInt16(nextY)
        let x = lastAbsX
        let y = lastAbsY
        let btns = activeButtons
        lock.unlock()
        transmitMouseReport(HIDMouseReport(buttons: btns, x: x, y: y, wheel: wheel))
    }

    /// Builds a mouse report at the current absolute cursor without changing position.
    func currentAbsoluteReport(buttons: UInt8) -> HIDMouseReport {
        lock.lock()
        defer { lock.unlock() }
        return HIDMouseReport(buttons: buttons, x: lastAbsX, y: lastAbsY, wheel: 0)
    }

    /// Presses and releases the left button at the current absolute position.
    func clickLeft() async throws {
        let down = setButton(.left, pressed: true)
        transmitMouseReport(currentAbsoluteReport(buttons: down))
        defer {
            let up = setButton(.left, pressed: false)
            transmitMouseReport(currentAbsoluteReport(buttons: up))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
    }

    /// Synthesizes a directional swipe via a short absolute drag path.
    func performSwipe(_ direction: SwipeDirection) async throws {
        let start: (Double, Double)
        let end: (Double, Double)
        switch direction {
        case .up:
            start = (0.5, 0.85)
            end = (0.5, 0.25)
        case .down:
            start = (0.5, 0.25)
            end = (0.5, 0.85)
        case .left:
            start = (0.8, 0.5)
            end = (0.2, 0.5)
        case .right:
            start = (0.2, 0.5)
            end = (0.8, 0.5)
        }
        try await performDrag(from: start, to: end, steps: 5, stepDelayNs: 20_000_000, holdAtEndNs: 0)
    }

    /// Drags with left button held from `start` to `end` in discrete absolute steps.
    func performDrag(
        from start: (Double, Double),
        to end: (Double, Double),
        steps: Int,
        stepDelayNs: UInt64,
        holdAtEndNs: UInt64
    ) async throws {
        let count = max(steps, 2)
        movePointerAbsolute(normalizedX: start.0, normalizedY: start.1)
        try await Task.sleep(nanoseconds: 20_000_000)
        let down = setButton(.left, pressed: true)
        transmitMouseReport(currentAbsoluteReport(buttons: down))
        defer {
            let up = setButton(.left, pressed: false)
            transmitMouseReport(currentAbsoluteReport(buttons: up))
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        for index in 1 ... count {
            let progress = Double(index) / Double(count)
            let x = start.0 + (end.0 - start.0) * progress
            let y = start.1 + (end.1 - start.1) * progress
            movePointerAbsolute(normalizedX: x, normalizedY: y)
            try await Task.sleep(nanoseconds: stepDelayNs)
        }

        if holdAtEndNs > 0 {
            try await Task.sleep(nanoseconds: holdAtEndNs)
        }
    }

    /// Sends a key-down then immediate key-up chord for a single HID usage.
    func sendKeyChord(modifiers: UInt8, keyCode: UInt8) async throws {
        transmitKeyboardReport(HIDKeyboardReport(modifiers: modifiers, keyCodes: [keyCode]))
        defer {
            transmitKeyboardReport(HIDKeyboardReport(modifiers: 0, keyCodes: []))
        }
        try await Task.sleep(nanoseconds: HIDTiming.shortGapNs)
    }

    /// Pulses a consumer-control usage (press then release to 0).
    func sendConsumerPulse(_ usage: ConsumerUsage) async throws {
        transmitConsumerReport(usage.rawValue)
        defer {
            transmitConsumerReport(0)
        }
        try await Task.sleep(nanoseconds: HIDTiming.shortGapNs)
    }
}
