# Security Policy — MacPhoneMirror

## Security Architecture

MacPhoneMirror is engineered around privacy and system integrity.

### 1. Platform & API Guarantees
* **No Jailbreaks**: MacPhoneMirror requires no jailbreaking, modified iOS kernels, or unauthorized system hooks.
* **No Private APIs**: MacPhoneMirror utilizes only documented, public Apple frameworks (`AVFoundation`, `VideoToolbox`, `Metal`, `Network`, `CoreBluetooth`, `AppKit`, `SwiftUI`).
* **Zero Cloud Dependence**: All video decoding, coordinate mapping, and Bluetooth communications are processed entirely locally on your Mac. No video, audio, keystrokes, or screen contents leave your local device.

### 2. Permissions Policy
MacPhoneMirror requests only the permissions strictly required to perform its functions:
* **Screen / Device Capture (`AVCaptureDevice`)**: Required by macOS to capture tethered iOS device video over USB.
* **Bluetooth (`CoreBluetooth`)**: Required to pair with the iPhone as a Bluetooth HID device for mouse and keyboard control.
* **Local Network (`Network.framework`)**: Required to browse Bonjour AirPlay services on the local Wi-Fi subnet.

MacPhoneMirror will **never** log passwords, keystrokes, personal messages, or user credentials.

### 3. Reporting a Vulnerability
If you discover a potential security issue in MacPhoneMirror, please open a private GitHub advisory or contact the maintainers directly. Vulnerabilities will be triaged and addressed promptly.
