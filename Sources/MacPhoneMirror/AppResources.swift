import AppKit
import Foundation

enum AppResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }

    static func image(forResource name: String, withExtension ext: String) -> NSImage? {
        guard let url = url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}
