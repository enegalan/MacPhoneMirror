import Foundation
import AVFoundation

enum DeviceDiscoveryFilter {
    private static let cameraNameTokens = ["cámara", "camera", "facetime", "continuity", "webcam"]

    static func isUSBPhoneScreenDevice(_ device: AVCaptureDevice) -> Bool {
        guard device.deviceType == .external else { return false }

        let name = device.localizedName.lowercased()
        if cameraNameTokens.contains(where: { name.contains($0) }) {
            return false
        }

        return device.manufacturer.contains("Apple") || name.contains("iphone") || name.contains("ipad")
    }

    static func isLikelyPhoneName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("iphone")
            || lower.contains("ipad")
            || (isLikelyBonjourPhoneName(name) && !lower.contains("appletv") && !lower.contains("macbook"))
    }

    static func isLikelyBonjourPhoneName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("@") || lower.contains("fe80") || lower.contains("supportsrp") {
            return false
        }

        let colonCount = name.filter { $0 == ":" }.count
        if colonCount >= 3 {
            return false
        }

        if name.isEmpty || name.count > 64 {
            return false
        }

        return name.rangeOfCharacter(from: .letters) != nil
    }

    static func normalizedDeviceKey(from name: String) -> String {
        if let start = name.firstIndex(of: "\""),
           let end = name.lastIndex(of: "\""),
           start < end {
            let extracted = String(name[name.index(after: start)..<end])
            if !extracted.isEmpty {
                return extracted.lowercased()
            }
        }

        var normalized = name
        let prefixes = ["cámara de ", "camera of ", "cámara ", "camera "]
        for prefix in prefixes where normalized.lowercased().hasPrefix(prefix) {
            normalized = String(normalized.dropFirst(prefix.count))
            break
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func mergeDiscoveredDevices(
        usb: [PhoneDevice],
        bonjour: [PhoneDevice],
        bluetooth: [PhoneDevice]
    ) -> [PhoneDevice] {
        var combined: [PhoneDevice] = []
        var seenKeys = Set<String>()

        for device in usb where device.supportsScreenMirroring {
            let key = normalizedDeviceKey(from: device.name)
            combined.append(device)
            seenKeys.insert(key)
        }

        for device in bonjour where device.canConnect {
            let key = normalizedDeviceKey(from: device.name)
            if !seenKeys.contains(key) {
                combined.append(device)
                seenKeys.insert(key)
            }
        }

        for device in bluetooth where device.canConnect {
            let key = normalizedDeviceKey(from: device.name)
            if !seenKeys.contains(key) {
                combined.append(device)
                seenKeys.insert(key)
            }
        }

        return combined
    }
}
