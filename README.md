<p align="center">
  <img src="art/logo-brand.png" alt="MacPhoneMirror" width="400"/>
  <br>
  <strong>Mirror your iPhone's screen on your Mac — and tap and drag it with your mouse or trackpad.</strong><br/>
  A fast, native macOS app that turns your Mac into a full-size iPhone display you can actually use.
</p>

<p align="center">
  <a href="https://enegalan.github.io/MacPhoneMirror/">Official website</a>
  ·
  <a href="https://github.com/enegalan/MacPhoneMirror/releases/latest">Download</a>
</p>

---
<p align="center">
  <a href="https://github.com/enegalan/MacPhoneMirror/actions/workflows/ci.yml">
    <img src="https://github.com/enegalan/MacPhoneMirror/actions/workflows/ci.yml/badge.svg"/>
  </a>
</p>

## What you can do

* 📱 **Mirror your iPhone** — See your phone's screen on your Mac over AirPlay Screen Mirroring (or USB when available).
* 🖱️ **Tap & drag from your Mac** — With AssistiveTouch pointer control, use mouse or trackpad taps and drags on the mirrored screen. Scroll and gestures are click-drag only (no keyboard shortcuts).
* 🪟 **Screen-shaped windows** — The mirror video fills the whole window (rounded like an iPhone screen). One window per phone so you can mirror several devices at once.
* 🔒 **Private & legit** — Runs entirely on your Mac, needs no jailbreak or separate app on your phone.

---

## Getting started

### What you'll need
* macOS 14.0+ (Sonoma) or newer
* An Apple Silicon (M1/M2/M3/M4) or Intel Mac
* An iPhone that supports Screen Mirroring
* AssistiveTouch enabled on the iPhone if you want pointer control (see the in-app Control guide)

### Run it
```bash
# Clone the repository
git clone https://github.com/enegalan/MacPhoneMirror.git
cd MacPhoneMirror

# Build and run
swift run MacPhoneMirror
```

1. Enable the AirPlay service in the **Service** tab.
2. On iPhone, open **Screen Mirroring** and pick your Mac.
3. Pair Bluetooth HID / enable AssistiveTouch if you want taps and drags (Control tab).

---

## How it works

> New to the technical details? You don't need any of this to use the app.

MacPhoneMirror advertises as an AirPlay receiver, decodes the mirror stream on Mac, and optionally acts as a Bluetooth HID pointer for AssistiveTouch. Input is limited to absolute pointer taps and drags — not keyboard injection or system shortcuts. If you're curious about the engineering, read [FEASIBILITY.md](FEASIBILITY.md).

---

## License

This project is licensed under the [MIT License](LICENSE).
