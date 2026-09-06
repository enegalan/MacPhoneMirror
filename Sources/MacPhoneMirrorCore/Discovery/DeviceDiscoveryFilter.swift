import AVFoundation
import Foundation

// Distinguishes USB iPhone screen muxed devices from Continuity Camera.
// Without this filter, Continuity Camera would be treated as a phone to mirror.

enum DeviceDiscoveryFilter {
    /// USB iPhone/iPad screen capture appears as an external **muxed** device.
    /// Continuity Camera appears as external **video** (not muxed).
    /// Filtering on muxed+Apple avoids treating Continuity Camera as a phone to mirror.
    static func isUSBPhoneScreenDevice(_ device: AVCaptureDevice) -> Bool {
        guard device.deviceType == .external else { return false }
        guard device.hasMediaType(.muxed) else { return false }

        let manufacturer = device.manufacturer.lowercased()
        return manufacturer.contains("apple") || manufacturer.isEmpty
    }
}
