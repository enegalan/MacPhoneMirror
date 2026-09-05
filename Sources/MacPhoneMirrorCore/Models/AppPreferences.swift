import Foundation

/// Typed UserDefaults keys shared by Settings/Control UI and Core readers.
public enum AppPreferences {
    public enum Key {
        public static let enableHardwareDecode = "enableHardwareDecode"
        public static let lowLatencyMode = "lowLatencyMode"
        public static let frameStyle = "frameStyle"
        public static let enableMouseControl = "control.enableMouseControl"
        public static let showTouchRipples = "control.showTouchRipples"
        public static let mouseSensitivity = "control.mouseSensitivity"
    }

    public static var enableHardwareDecode: Bool {
        get { UserDefaults.standard.object(forKey: Key.enableHardwareDecode) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.enableHardwareDecode) }
    }

    public static var lowLatencyMode: Bool {
        get { UserDefaults.standard.object(forKey: Key.lowLatencyMode) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.lowLatencyMode) }
    }

    public static var enableMouseControl: Bool {
        get { UserDefaults.standard.object(forKey: Key.enableMouseControl) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.enableMouseControl) }
    }

    public static var showTouchRipples: Bool {
        get { UserDefaults.standard.object(forKey: Key.showTouchRipples) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showTouchRipples) }
    }

    public static var mouseSensitivity: Double {
        get {
            let value = UserDefaults.standard.object(forKey: Key.mouseSensitivity) as? Double
            return value ?? 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.mouseSensitivity) }
    }

    public static var frameStyle: FrameRenderStyle {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.frameStyle),
                  let style = try? JSONDecoder().decode(FrameRenderStyle.self, from: data)
            else { return .standard }
            return style
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Key.frameStyle)
            }
        }
    }
}
