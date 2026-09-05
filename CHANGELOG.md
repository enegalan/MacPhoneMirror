# Changelog

## [1.4] - 2026-09-05

### Added

- Launch at Login via `SMAppService`
- Hardware VideoToolbox and low-latency decode toggles wired to the video pipeline
- Shared persisted Appearance settings applied to live mirror windows
- Control preferences wired: mouse gate, touch ripples, sensitivity
- Unit tests for AppPreferences, Ultra vs High stream sizes, and pointer input gates
- How to Connect button on the Service page

### Fixed

- Rapid AirPlay service toggle no longer races start/stop (stale starts cannot clear a newer listener or leave Bonjour half-registered)
- Mirror TCP accept socket shuts down with the AirPlay service so reconnects get a clean dataPort
- Failed VideoToolbox decodes no longer double-decrement the in-flight frame counter (low-latency drop accounting)

### Changed

- Ultra stream quality advertises a larger point and pixel size than High
- STREAM negotiation XML includes pixel dimensions
- Stream resolution UI notes that changes apply on the next AirPlay connection
- Low-latency mode allows up to 5 in-flight decode frames before dropping (was 2)
- New Finder / Dock app icon (with background); menu bar keeps the transparent logo
- Connection and AssistiveTouch guides rewritten in plain language for end users
- SwiftLint is clean

### Removed

- Keyboard shortcuts for AssistiveTouch actions (unreliable on macOS / HID)
- Invert Scroll option and wheel-scroll capture (scroll via click-drag only)
- Non-functional "Auto-start screen mirroring on connect" setting

## [1.3.5] - 2026-09-04

### Fixed

- AirPlay service toggle can re-enable advertising after disable (listening flag was never cleared)
- Stale AirPlay session keys / open connections no longer linger after disconnect or service stop
- Listener cancel no longer races with restart and marks a fresh listener as stopped

### Removed

- Unused "Auto-connect to last known iPhone" setting

## [1.3] - 2026-09-04

### Added

- Bluetooth HID remote control: Mac advertises as a mouse/keyboard for iOS AssistiveTouch pairing
- Absolute pointer coordinates so taps land on the mirrored screen position
- Click-drag in the mirror viewport (pointer down/move/up) for scroll and swipe gestures
- `NSBluetoothAlwaysUsageDescription` for Bluetooth permission prompting
- AirPlay audio stream handling so playing media on the iPhone no longer drops the mirror session

### Changed

- Bluetooth HID advertising starts with the AirPlay service so AssistiveTouch can pair before mirroring
- Mirror window scales the phone frame to fit, including landscape in a portrait-shaped window
- Smaller minimum mirror window size
- Bluetooth HID reports are queued instead of dropped when the radio is busy
- Pointer gestures wait for in-flight HID reports so taps and drags complete reliably

### Fixed

- Audio-only TEARDOWN no longer closes the video session
- Bluetooth HID advertising timeout no longer hangs pairing
- Phone frame no longer clips when the window is resized

### Removed

- Test Pattern diagnostic from the menu bar and app UI (dev-only; not needed by end users)
- Dynamic Island / Notch overlay from the phone frame and Appearance settings
- Quick Controls bar from the mirror window

## [1.2.5] - 2026-09-04

### Fixed

- Release builds no longer close the AirPlay mirror socket before video arrives
- Idle timeout now uses wall-clock time instead of a recv iteration count
- Restored session windows no longer stick on "Connecting…" with no live session
- Closing a session window no longer tears down AirPlay during SwiftUI reparent/layout (`onDisappear`); teardown runs on real window close

### Changed

- Mirror stream read loop runs on a dedicated queue so accept stays responsive
- Removed `SO_REUSEPORT` from the mirror listener to avoid duplicate-bind / RST issues

## [1.2] - 2026-09-04

### Added

- Synthetic test-pattern session to diagnose black-screen issues without an iPhone
- Menu bar action and window group to launch the test pattern

## [1.1.5] - 2026-09-03

### Fixed

- App icon now embeds correctly in the packaged `.app`

### Changed

- Centralized logo/resource loading via `AppResources`

## [1.1] - 2026-09-03

### Added

- Redesigned settings UI for AirPlay mirroring configuration
- Dynamic menu bar status icon reflecting service and session state
- Ad-hoc signing with network entitlement verification in the build script

### Changed

- Redesigned macOS menu actions and menu bar extra
- Refactored AirPlay service management and related UI components
- About window handling uses shared app info helpers

### Removed

- Session status badge from the main UI surfaces

## [1.0.0] - 2026-09-02

### Added

- AirPlay receiver that mirrors iPhone/iPad screen to Mac
- Bonjour service advertisement for device discovery
- Session management for AirPlay connections
- App icon and branding
- SwiftLint and SwiftFormat configuration
- CI pipeline with lint, format, build, and test jobs
- Architecture documentation (ARCHITECTURE.md)
- Security policy (SECURITY.md)
- Contributing guidelines (CONTRIBUTING.md)
- MIT License
