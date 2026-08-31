# MacPhoneMirror — macOS iPhone Screen Mirroring & Control

<p align="center">
  <strong>See your iPhone. Control it from your Mac.</strong><br/>
  A high-performance, native macOS application for low-latency iPhone screen mirroring, realistic titanium device framing, and Mac-to-iPhone interaction.
</p>

---

## Highlights

* 📱 **Ultra-Low Latency Screen Mirroring**: 60 FPS hardware-accelerated mirroring via USB (AVFoundation) and Wi-Fi AirPlay receivers.
* ⚡ **Hardware Video Pipeline**: Zero-copy Metal rendering with `VideoToolbox` hardware H.264/HEVC decompression.
* 🖱️ **Mac-to-iPhone Interaction**: Smooth mouse/trackpad pointer control, scrolling, and clicks via Bluetooth HID + iOS AssistiveTouch.
* ⌨️ **Hardware Keyboard Navigation**: Type into iOS apps and trigger system shortcuts (`⌘H` for Home, `⌘Tab` for App Switcher, `⌘Space` for Spotlight, `Esc` to Lock).
* 🎨 **High-Fidelity iPhone Frames**: Vector-rendered titanium chassis (Natural, Black, Desert, White, Deep Purple) with squircle screen clipping, animated Dynamic Island, and interactive hardware buttons.
* 📊 **Real-Time Performance HUD**: Live overlay tracking FPS, decode latency, render latency, bit rate, and dropped frames.
* 🧭 **Menu Bar Extra**: macOS status bar item for quick mirroring toggles and orientation switching.
* 🔒 **100% Legitimate & Private**: Uses public Apple APIs, requires no jailbreak or companion iOS app, and processes all video strictly locally.

---

## Quick Start

### Requirements
* macOS 14.0+ (Sonoma) or macOS 15.0+ (Sequoia)
* Apple Silicon (M1/M2/M3/M4) or Intel Mac

### Build & Run
```bash
# Clone repository
git clone https://github.com/enegalan/MacPhoneMirror.git
cd MacPhoneMirror

# Build executable
swift build

# Run unit tests
swift test

# Run MacPhoneMirror
swift run MacPhoneMirror
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘H` | Go to iOS Home Screen |
| `⌘Tab` | Open iOS App Switcher |
| `Esc` | Lock / Wake iPhone Screen |

---

## Platform & Technical Feasibility

MacPhoneMirror provides an honest, production-quality implementation respecting Apple's platform security model:
* **Mirroring**: Uses native AVFoundation USB screen capture for sub-10ms latency and 60 FPS, with fallback to Bonjour network streaming.
* **Control**: Leverages standard Bluetooth HID profiles combined with iOS AssistiveTouch to provide legitimate cursor navigation, clicking, dragging, scrolling, and keyboard typing without requiring iOS kernel modifications.

See [FEASIBILITY.md](FEASIBILITY.md) for full technical documentation.

---

## License

This project is licensed under the [MIT License](LICENSE).
