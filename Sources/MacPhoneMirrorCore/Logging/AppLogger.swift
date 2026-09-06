import Foundation
import os

// os.Logger facade with app-specific categories.
// Central place to filter/inspect logs without scattering Logger(subsystem:) calls.

public enum LogCategory: String {
    case device = "Device"
    case network = "Network"
    case airplay = "AirPlay"
    case video = "Video"
    case input = "Input"
    case bluetooth = "Bluetooth"
    case ui = "UI"
    case security = "Security"
    case session = "Session"
}

public enum AppLogger {
    private static let subsystem = "com.macphonemirror.app"

    private nonisolated(unsafe) static var loggers: [LogCategory: Logger] = [:]
    private static let lock = NSLock()

    /// Returns a cached `os.Logger` for the category, creating it on first use.
    public static func logger(for category: LogCategory) -> Logger {
        lock.lock()
        defer { lock.unlock() }

        if let existing = loggers[category] {
            return existing
        }
        let newLogger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = newLogger
        return newLogger
    }

    /// Logs at debug; not echoed to stderr.
    public static func debug(_ message: String, category: LogCategory) {
        logger(for: category).debug("\(message, privacy: .public)")
    }

    /// Logs at info and echoes selected categories to stderr for console visibility.
    public static func info(_ message: String, category: LogCategory) {
        logger(for: category).info("\(message, privacy: .public)")
        echoToConsole(message, category: category, level: "INFO")
    }

    /// Logs at notice and echoes selected categories to stderr.
    public static func notice(_ message: String, category: LogCategory) {
        logger(for: category).notice("\(message, privacy: .public)")
        echoToConsole(message, category: category, level: "NOTICE")
    }

    /// Logs at warning and echoes selected categories to stderr.
    public static func warning(_ message: String, category: LogCategory) {
        logger(for: category).warning("\(message, privacy: .public)")
        echoToConsole(message, category: category, level: "WARN")
    }

    /// Logs at error and echoes selected categories to stderr.
    public static func error(_ message: String, category: LogCategory) {
        logger(for: category).error("\(message, privacy: .public)")
        echoToConsole(message, category: category, level: "ERROR")
    }

    /// Mirrors high-signal categories (AirPlay/session/network/Bluetooth) to stderr.
    private static func echoToConsole(_ message: String, category: LogCategory, level: String) {
        guard category == .airplay
            || category == .session
            || category == .network
            || category == .bluetooth
        else { return }
        let line = "[\(AppInfo.name)][\(category.rawValue)][\(level)] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
