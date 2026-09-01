# MacPhoneMirror Architecture Documentation

## Overview

MacPhoneMirror is structured with a modular, protocol-oriented Swift 6 architecture separating business logic, hardware abstraction, video rendering, input mapping, and UI presentation.

```text
┌────────────────────────────────────────────────────────────────────────┐
│                          MacPhoneMirror (App)                          │
│          App Entry, NSApplicationDelegate, Keyboard Shortcuts          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
        ┌───────────────────────────┴───────────────────────────┐
        ▼                                                       ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│       MacPhoneMirrorUI        │               │      MacPhoneMirrorCore       │
│  - MainWindowView & Sidebar   │◄──────────────┤  - State Machine & Session    │
│  - Realistic iPhone Frame     │ (State &      │  - Video Pipeline & Metal     │
│  - MetalVideoView MTKView     │  Receivers)   │  - Input & Coordinate Mapper  │
│  - Diagnostics & HUD Overlay  │               │  - Device Discovery           │
│  - Device List & Pairing View │               │  - Bluetooth HID Transport    │
│  - Settings & Preferences     │               │  - Structured Logger          │
└───────────────────────────────┘               └───────────────────────────────┘
```

---

## 1. Core Modules & Protocols

### `MacPhoneMirrorCore`

#### A. Discovery Layer (`DeviceDiscovery`)
* `DeviceDiscovery`: Protocol for reactive device scanning.
* `USBDeviceDiscovery`: Listens to `AVCaptureDevice` connect/disconnect events.
* `BonjourDiscovery`: Scans for `_airplay._tcp` Bonjour services using `Network.framework`.
* `BluetoothDiscovery`: CoreBluetooth `CBCentralManager` scanning.
* `CompositeDiscovery`: Aggregates and deduplicates discovered devices into a unified reactive stream.

#### B. Screen Mirroring (`ScreenMirrorReceiver`)
* `ScreenMirrorReceiver`: Core protocol defining `start()`, `stop()`, and `framePublisher: AnyPublisher<VideoFrame, Never>`.
* `AVFoundationUSBReceiver`: High-speed USB screen capture receiver with zero external dependencies.
* `NetworkStreamReceiver`: AirPlay network receiver handling RTP packet parsing and decompression.
* `TestPatternReceiver`: Real-time 60 FPS interactive iOS display simulator.

#### C. Video Pipeline
* `VideoFrame`: Holds `CVPixelBuffer`, orientation, presentation timestamp, and capture time.
* `VideoDecoder`: VideoToolbox `VTDecompressionSession` for hardware-accelerated H.264/HEVC decoding.
* `MetalVideoRenderer`: Zero-copy Metal texture rendering with `MTKViewDelegate` and custom shaders.
* `PerformanceMonitor`: Thread-safe tracker measuring FPS, decode latency, render latency, bit rate, and dropped frames.

#### D. Input & Control Subsystem
* `InputCoordinateMapper`: Translates Mac window click/drag coordinates into iPhone normalized screen coordinates and native pixel coordinates.
* `PhoneInputTransport`: Protocol for transmitting input events (`pointerMove`, `pointerDown`, `pointerUp`, `keyDown`, `scroll`, `homeButton`, `appSwitcher`, `lockScreen`).
* `BluetoothHIDTransport`: Formats and sends standard HID mouse, keyboard, and consumer control reports.
* `AssistiveTouchProfile`: Predefined actions and shortcuts for navigating iOS with AssistiveTouch.
* `KeyboardShortcutMapper`: Translates Mac key codes into USB HID usage codes.

#### E. State Machine & Session Manager
* `ConnectionState`: State enum (`disconnected`, `discovering`, `connecting`, `mirroring`, `controlling`, `reconnecting`, `failed`).
* `SessionManager`: Singleton coordinating active device, receiver, input transport, orientation, and diagnostics.

---

## 2. UI Layer (`MacPhoneMirrorUI`)

* **`MainWindowView`**: Unified navigation split view with sidebar, live video viewport, and toolbar.
* **`PhoneFrameView`**: Vector-rendered realistic iPhone chassis with titanium finishes, squircle screen clipping, dynamic island, notch, and clickable hardware buttons.
* **`DynamicIslandView`**: Animated Dynamic Island with compact, expanded media, and notification states.
* **`DiagnosticsOverlayView`**: Live HUD displaying real-time FPS, decode latency, render latency, and bit rate.
* **`QuickControlsBar`**: Floating controls for Home (`⌘H`), App Switcher (`⌘Tab`), and Lock (`Esc`). Orientation follows the mirrored device automatically.
* **`DeviceListView` & `PairingGuideView`**: Device management and interactive pairing walkthroughs.
* **`ControlConfigView` & `AssistiveTouchGuideView`**: Visual instructions for enabling AssistiveTouch pointer control on iPhone.
* **`SettingsView`**: Preferences for video quality, appearance, input sensitivity, and permissions.

---

## 3. Concurrency & Swift 6 Safety

* All asynchronous methods strictly avoid holding `NSLock` across suspension points.
* Data models (`PhoneDevice`, `PhoneModel`, `VideoFrame`, `StreamStatistics`) conform to `Sendable`.
* AppKit lifecycle and UI-bound methods are isolated with `@MainActor`.
