# MacPhoneMirror Architecture Documentation

## Overview

MacPhoneMirror is a macOS AirPlay **receiver** app with a modular Swift 6 layout: Core holds session, video, input, and discovery; UI presents Service / Control / Settings and per-device mirror windows.

```text
┌────────────────────────────────────────────────────────────────────────┐
│                          MacPhoneMirror (App)                          │
│              App Entry, NSApplicationDelegate, Menu Bar                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
        ┌───────────────────────────┴───────────────────────────┐
        ▼                                                       ▼
┌────────────────────────────────┐               ┌───────────────────────────────┐
│       MacPhoneMirrorUI         │               │      MacPhoneMirrorCore       │
│  - MainWindowView & Sidebar    │◄──────────────┤  - SessionManager             │
│  - Service / Control / Settings│ (State &      │  - AirPlay receiver stack     │
│  - PhoneFrame + MetalVideo     │  Receivers)   │  - USB capture + HID input    │
│  - MirrorSessionWindow         │               │  - Video pipeline & Metal     │
│  - PairingGuideView            │               │  - AppLogger                  │
└────────────────────────────────┘               └───────────────────────────────┘
```

Runtime flow is **receiver-first**:

1. User enables the AirPlay service (Service tab).
2. Mac advertises via Bonjour (`_airplay._tcp`); iPhone connects with Screen Mirroring.
3. Optional USB iPhone screen devices auto-open a mirror session.
4. Each active device gets its own `MirrorSessionWindow`.

---

## 1. Core Modules & Protocols

### `MacPhoneMirrorCore`

#### A. Discovery Layer (`DeviceDiscovery`)
* `DeviceDiscovery`: Protocol for reactive device scanning.
* `USBDeviceDiscovery`: Listens to `AVCaptureDevice` connect/disconnect events for wired screen devices.
* `DeviceDiscoveryFilter`: Distinguishes USB phone screen capture from Continuity Camera.

AirPlay does **not** browse remote phones; the Mac is the advertised receiver.

#### B. Screen Mirroring (`ScreenMirrorReceiver`)
* `ScreenMirrorReceiver`: Protocol with `start()`, `stop()`, and `framePublisher`.
* `NetworkStreamReceiver`: AirPlay control listener, session lifecycle, and frame fan-out.
* `AVFoundationUSBReceiver`: USB screen capture.

Supporting AirPlay pieces: `AirPlayConnectionHandler`, `AirPlayMirrorServer`, `AirPlayAudioServer`, `AirPlayTimingServer`, `AirPlayIdentity` / pairing PIN display, FairPlay / crypto helpers.

#### C. Video Pipeline
* `VideoFrame`: `CVPixelBuffer`, orientation, timestamps.
* `VideoDecoder` / `AirPlayH264Decoder`: VideoToolbox H.264 / HEVC decode for the mirror stream.
* `MetalVideoRenderer`: Zero-copy Metal texture rendering for `MTKView`.

#### D. Input & Control
* `InputCoordinateMapper`: Viewport → normalized phone coordinates.
* `PhoneInputTransport`: Protocol for pointer / button events.
* `BluetoothHIDTransport`: BLE HID peripheral for AssistiveTouch pointer control.
* `SimulatedInputTransport`: Test / fallback transport.

#### E. State Machine & Session Manager
* `ConnectionState`: `disconnected`, `discovering`, `connecting`, `mirroring`, `failed`.
* `SessionManager`: Facade over `MirrorSessionStore`, `AirPlayServiceController`, `USBAutoConnectCoordinator`, and `SessionInputRouter`. Opens/closes `MirrorSessionWindow` via publishers.

---

## 2. UI Layer (`MacPhoneMirrorUI`)

* **`MainWindowView`**: Navigation split (Service, Control, Settings) plus sidebar of active sessions.
* **`ServiceView`**: AirPlay service toggle, device name, pairing PIN when required, connected devices.
* **`ControlConfigView`** / **`AssistiveTouchGuideView`**: Pointer control setup on iPhone.
* **`PairingGuideView`**: How to connect walkthrough.
* **`PhoneFrameView`**: Vector iPhone chassis.
* **`MirrorViewportView`** / **`MetalVideoView`**: Live mirror surface and input forwarding.
* **`MirrorSessionWindow`**: One window per mirrored device.
* **`SettingsView`**: Quality, appearance, input, permissions, launch at login, audio toggles.
* **`MenuBarExtraView`**: Menu bar status and quick actions.

---

## 3. Concurrency & Swift 6 Safety

* Avoid holding `NSLock` across `await` / suspension points.
* Models (`PhoneDevice`, `PhoneModel`, `VideoFrame`) are `Sendable`.
* AppKit / SwiftUI-bound updates use the main queue or `@MainActor` where required.
* Network, HID, and decode work stay on dedicated `DispatchQueue`s.
