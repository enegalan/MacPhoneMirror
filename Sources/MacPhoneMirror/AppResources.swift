import AppKit
import Foundation

// Bundled assets resolver for either the app bundle or the SPM module bundle.
// Debug/SPM vs packaged .app load resources from different Bundle roots.

enum AppResources {
    private static let spmBundleName = "MacPhoneMirror_MacPhoneMirror.bundle"

    /// Resolves a resource URL from `Bundle.main`, then the SPM resource bundle if present.
    /// Returns nil when the asset is missing. Never uses `Bundle.module` — SPM's accessor
    /// `fatalError`s when a packaged `.app` omits the resource bundle.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return spmResourceBundle()?.url(forResource: name, withExtension: ext)
    }

    /// Loads an `NSImage` from a bundled resource; returns nil if the URL or image load fails.
    static func image(forResource name: String, withExtension ext: String) -> NSImage? {
        guard let url = url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Soft-loads the SPM resource bundle used by `swift run` / debug builds.
    private static func spmResourceBundle() -> Bundle? {
        let candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent(spmBundleName),
            Bundle.main.resourceURL?.appendingPathComponent(spmBundleName),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(spmBundleName),
        ].compactMap(\.self)

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }
}
