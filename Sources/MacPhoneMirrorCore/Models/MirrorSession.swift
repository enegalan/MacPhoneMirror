import Foundation

public struct MirrorSession: Identifiable, Hashable, Sendable {
    public let id: String
    public var device: PhoneDevice
    public var orientation: DeviceOrientation

    public init(
        id: String = UUID().uuidString,
        device: PhoneDevice,
        orientation: DeviceOrientation = .portrait
    ) {
        self.id = id
        self.device = device
        self.orientation = orientation
    }
}

public enum MirrorWindowID {
    public static let main = "main"
    public static let session = "mirror-session"
    public static let about = "about"
}
