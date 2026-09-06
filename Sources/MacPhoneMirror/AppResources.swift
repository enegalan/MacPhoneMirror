import AppKit
import Foundation

// Bundled assets resolver for either the app bundle or the SPM module bundle.
// Debug/SPM vs packaged .app load resources from different Bundle roots.

enum AppResources {
    /// Resolves a resource URL from `Bundle.main`, then falls back to `Bundle.module`.
    /// Returns nil when the asset is missing from both bundles.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }

    /// Loads an `NSImage` from a bundled resource; returns nil if the URL or image load fails.
    static func image(forResource name: String, withExtension ext: String) -> NSImage? {
        guard let url = url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}
