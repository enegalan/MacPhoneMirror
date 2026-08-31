# Contributing to MacPhoneMirror

Thank you for your interest in contributing to **MacPhoneMirror**!

## Development Setup

MacPhoneMirror is built using standard Swift Package Manager and Xcode tools:

### Requirements
* macOS 14.0 (Sonoma) or macOS 15.0 (Sequoia)
* Swift 6.0+ (Xcode 16+ or Command Line Tools)
* Apple Silicon or Intel Mac

### Building the Project
Clone the repository and build using Swift Package Manager:
```bash
git clone https://github.com/enegalan/MacPhoneMirror.git
cd MacPhoneMirror
swift build
```

### Running Unit & Integration Tests
```bash
swift test
```

### Running the Application
```bash
swift run MacPhoneMirror
```

---

## Coding Standards

* **Native Swift & SwiftUI**: Follow Apple's Human Interface Guidelines.
* **Concurrency**: Ensure code conforms to Swift 6 strict concurrency rules (`Sendable`, `@MainActor`, async-safe state management).
* **Logging**: Use `AppLogger` categories rather than raw `print()` statements.
* **Testing**: Add unit tests in `Tests/MacPhoneMirrorTests/` using the Swift Testing framework (`import Testing`, `@Test`, `#expect`).
