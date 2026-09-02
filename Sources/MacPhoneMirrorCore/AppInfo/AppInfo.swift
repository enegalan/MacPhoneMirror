import Foundation

public enum AppInfo {
    public static let bundle: Bundle = .main

    public static var name: String {
        bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "MacPhoneMirror"
    }

    public static var displayName: String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? name
    }

    public static var version: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    public static var build: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    public static var copyright: String {
        bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© \(Calendar.current.component(.year, from: Date())) \(name)"
    }
}
