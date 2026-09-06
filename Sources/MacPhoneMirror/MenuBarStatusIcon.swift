import AppKit
import MacPhoneMirrorCore
import SwiftUI

// Menu bar icon: base logo + status badge for service/session/failure.

enum MenuBarStatusIcon {
    private static let logoSize = NSSize(width: 24, height: 24)

    /// Builds the menu-bar image: white logo plus optional status badge.
    /// Returns nil when the bundled logo asset cannot be loaded.
    static func image(for serviceEnabled: Bool, sessions: Int, state: ConnectionState) -> NSImage? {
        guard let base = AppResources.image(forResource: "logo", withExtension: "png") else { return nil }

        let indicatorColor: NSColor = if sessions > 0 {
            .systemGreen
        } else if case .failed = state {
            .systemRed
        } else {
            .white
        }

        return compositedMenuBarImage(
            logo: base,
            indicatorColor: indicatorColor,
            showBadge: serviceEnabled
        )
    }

    /// Draws a white-tinted logo and optionally a colored wifi status badge.
    private static func compositedMenuBarImage(
        logo: NSImage,
        indicatorColor: NSColor,
        showBadge: Bool
    ) -> NSImage {
        let image = NSImage(size: logoSize)
        image.lockFocus()

        let logoRect = NSRect(x: 0, y: 0, width: logoSize.width, height: logoSize.height)

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

    /// Overlays a tinted SF Symbol wifi badge when the AirPlay service is enabled.
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

    /// Clears a rect in the current graphics context so the badge does not composite over noise.
    private static func clearRegion(_ rect: NSRect) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.clear(rect)
    }

    /// Returns a copy of `logo` filled with `color` via source-atop; never returns nil in practice.
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
