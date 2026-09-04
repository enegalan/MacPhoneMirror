# Changelog

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
