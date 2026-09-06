# Security Policy — MacPhoneMirror

## Security Architecture

MacPhoneMirror is engineered around privacy and system integrity.

### 1. Platform & API Guarantees
* **No Jailbreaks**: MacPhoneMirror requires no jailbreaking, modified iOS kernels, or unauthorized system hooks.
* **Public Apple frameworks**: Video capture, decode, render, networking, and HID use documented public APIs (`AVFoundation`, `VideoToolbox`, `Metal`, `Network`, `CoreBluetooth`, `AppKit`, `SwiftUI`).
* **FairPlay exception**: Unmanaged AirPlay Screen Mirroring also requires a repository-local, UxPlay-derived FairPlay implementation under `Sources/CAirPlayFairPlay` (Swift entry point: `AirPlayFairPlaySession.swift`). This is **not** an Apple public API and may affect App Store / notarization distribution options.
* **Zero Cloud Dependence**: All video decoding, coordinate mapping, and Bluetooth communications are processed entirely locally on your Mac. No video, audio, keystrokes, or screen contents leave your local device.

### 2. Permissions Policy
MacPhoneMirror requests only the permissions strictly required to perform its functions:
* **Screen / Device Capture (`AVCaptureDevice`)**: Required by macOS to capture tethered iOS device video over USB.
* **Bluetooth (`CoreBluetooth`)**: Required to pair with the iPhone as a Bluetooth HID pointer for AssistiveTouch taps and drags.
* **Local Network (`Network.framework`)**: Required to advertise this Mac as an AirPlay receiver and accept Screen Mirroring on the local Wi-Fi subnet.

MacPhoneMirror will **never** log passwords, keystrokes, personal messages, or user credentials.

### 3. Reporting a Vulnerability
If you discover a potential security issue in MacPhoneMirror, please open a private GitHub advisory or contact the maintainers directly. Vulnerabilities will be triaged and addressed promptly.
