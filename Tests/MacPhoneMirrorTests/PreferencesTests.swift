@testable import MacPhoneMirrorCore
import CoreGraphics
import Foundation
import Testing

// Unit tests for AppPreferences defaults and persistence round-trips.

@Suite(.serialized)
struct PreferencesTests {
    /// Clears preference keys, runs the body, then restores prior UserDefaults values.
    private func withCleanPreferences(_ body: () async -> Void) async {
        let keys = [
            AppPreferences.Key.enableHardwareDecode,
            AppPreferences.Key.lowLatencyMode,
            AppPreferences.Key.frameStyle,
            AppPreferences.Key.enableMouseControl,
            AppPreferences.Key.showTouchRipples,
            AppPreferences.Key.mouseSensitivity,
            AppPreferences.Key.streamQuality,
            AppPreferences.Key.airPlayServiceEnabled,
            AppPreferences.Key.enableAudioPlayback,
        ]
        let defaults = UserDefaults.standard
        var backup: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                backup[key] = value
            }
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                defaults.removeObject(forKey: key)
                if let value = backup[key] {
                    defaults.set(value, forKey: key)
                }
            }
        }
        await body()
    }

    /// Asserts AppPreferences.Key string constants stay stable for AppStorage.
    @Test func preferenceKeysAreStable() {
        #expect(AppPreferences.Key.streamQuality == "streamQuality")
        #expect(AppPreferences.Key.airPlayServiceEnabled == "airplay.serviceEnabled")
        #expect(AppPreferences.Key.enableHardwareDecode == "enableHardwareDecode")
        #expect(AppPreferences.Key.enableMouseControl == "control.enableMouseControl")
        #expect(AppPreferences.Key.enableAudioPlayback == "airplay.enableAudioPlayback")
    }

    /// Asserts factory defaults when preference keys are absent.
    @Test func appPreferencesDefaults() async {
        await withCleanPreferences {
            #expect(AppPreferences.enableHardwareDecode)
            #expect(AppPreferences.lowLatencyMode)
            #expect(AppPreferences.enableMouseControl)
            #expect(AppPreferences.showTouchRipples)
            #expect(AppPreferences.mouseSensitivity == 1.0)
            #expect(AppPreferences.frameStyle == .standard)
            #expect(AppPreferences.enableAudioPlayback)
        }
    }

    /// Asserts preference writes round-trip through UserDefaults.
    @Test func appPreferencesRoundTrip() async {
        await withCleanPreferences {
            AppPreferences.enableHardwareDecode = false
            AppPreferences.lowLatencyMode = false
            AppPreferences.enableMouseControl = false
            AppPreferences.showTouchRipples = false
            AppPreferences.mouseSensitivity = 1.5

            var style = FrameRenderStyle.standard
            style.displayMode = .borderless
            style.finish = .blackTitanium
            style.showShadow = false
            style.showReflection = false
            AppPreferences.frameStyle = style

            #expect(!AppPreferences.enableHardwareDecode)
            #expect(!AppPreferences.lowLatencyMode)
            #expect(!AppPreferences.enableMouseControl)
            #expect(!AppPreferences.showTouchRipples)
            #expect(AppPreferences.mouseSensitivity == 1.5)
            #expect(AppPreferences.frameStyle.displayMode == .borderless)
            #expect(AppPreferences.frameStyle.finish == .blackTitanium)
            #expect(!AppPreferences.frameStyle.showShadow)
            #expect(!AppPreferences.frameStyle.showReflection)
        }
    }

    /// Asserts ultra quality advertises larger dimensions than high at the same FPS.
    @Test func ultraAdvertisesLargerThanHigh() async {
        await withCleanPreferences {
            let ultra = StreamQuality.ultra
            let high = StreamQuality.high

            #expect(ultra.advertisedSize.width > high.advertisedSize.width)
            #expect(ultra.advertisedSize.height > high.advertisedSize.height)
            #expect(ultra.advertisedPixelSize.width > high.advertisedPixelSize.width)
            #expect(ultra.advertisedPixelSize.height > high.advertisedPixelSize.height)
            #expect(ultra.maxFPS == high.maxFPS)

            #expect(high.advertisedSize == CGSize(width: 402, height: 874))
            #expect(ultra.advertisedSize == CGSize(width: 440, height: 956))
        }
    }

    /// Asserts StreamConfiguration.shared persists quality changes.
    @Test func streamConfigurationPersistsQuality() async {
        await withCleanPreferences {
            StreamConfiguration.shared.quality = .balanced
            #expect(StreamConfiguration.shared.quality == .balanced)
            StreamConfiguration.shared.quality = .ultra
            #expect(StreamConfiguration.shared.quality == .ultra)
        }
    }

    /// Asserts disabled mouse control blocks pointer events until re-enabled.
    @Test func mouseControlGateBlocksPointerEvents() async {
        await withCleanPreferences {
            let manager = SessionManager()
            let device = PhoneDevice(
                name: "Gate Test",
                id: "gate-pointer-1",
                connectionType: .simulated
            )
            let transport = SimulatedInputTransport()
            let sessionID = manager.beginMirroringSession(
                device: device,
                receiver: StubScreenMirrorReceiver(),
                transport: transport,
                replaceExistingAirPlay: false
            )
            defer { manager.disconnect(sessionID: sessionID) }

            let viewport = CGSize(width: 402, height: 874)
            let point = CGPoint(x: 201, y: 437)

            AppPreferences.enableMouseControl = false
            await manager.handlePointerDown(at: point, viewportSize: viewport, sessionID: sessionID)
            await manager.handlePointerMove(at: point, viewportSize: viewport, sessionID: sessionID)
            await manager.handlePointerUp(at: point, viewportSize: viewport, sessionID: sessionID)
            #expect(transport.sentEventsCount == 0)

            AppPreferences.enableMouseControl = true
            await manager.handlePointerDown(at: point, viewportSize: viewport, sessionID: sessionID)
            #expect(transport.sentEventsCount == 2)
            #expect(transport.lastEvent == .pointerDown(button: .left))
        }
    }
}
