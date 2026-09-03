import AppKit
import MacPhoneMirrorCore
import SwiftUI

enum MenuBarStatusIcon {
    static func image(for serviceEnabled: Bool, sessions: Int, state: ConnectionState) -> NSImage? {
        guard let base = logoImage() else { return nil }

        let indicatorColor: NSColor
        if sessions > 0 {
            indicatorColor = .systemGreen
        } else if case .failed = state {
            indicatorColor = .systemRed
        } else {
            indicatorColor = .white
        }

        return compositedMenuBarImage(
            logo: base,
            indicatorColor: indicatorColor,
            showBadge: serviceEnabled
        )
    }

    private static func logoImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func compositedMenuBarImage(
        logo: NSImage,
        indicatorColor: NSColor,
        showBadge: Bool
    ) -> NSImage {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()

        let logoRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        guard let tinted = tintedLogo(logo, color: .white, in: logoRect) else {
            logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            image.unlockFocus()
            return image
        }
        tinted.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        if showBadge {
            drawStatusBadge(color: indicatorColor, in: image)
        }

        image.unlockFocus()
        return image
    }

    private static func drawStatusBadge(color: NSColor, in image: NSImage) {
        let canvasSize = image.size
        let badgeDimension = max(8, round(canvasSize.height * 0.01))
        let config = NSImage.SymbolConfiguration(pointSize: badgeDimension, weight: .semibold)
        guard let wifiSymbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
            .withSymbolConfiguration(config),
            let tintedBadge = tintedLogo(wifiSymbol, color: color, in: CGRect(origin: .zero, size: wifiSymbol.size))
        else { return }

        let badgeSize = wifiSymbol.size
        let marginX: CGFloat = round(canvasSize.height * 0)
        let marginY: CGFloat = round(canvasSize.height * 0.15)
        let badgeRect = NSRect(x: marginX, y: marginY, width: badgeSize.width, height: badgeSize.height)

        clearRegion(badgeRect.insetBy(dx: 1, dy: 0))

        tintedBadge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    private static func clearRegion(_ rect: NSRect) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.clear(rect)
    }

    private static func tintedLogo(_ logo: NSImage, color: NSColor, in rect: NSRect) -> NSImage? {
        let tinted = NSImage(size: rect.size)
        tinted.lockFocus()
        logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}
