import MacPhoneMirrorCore
import SwiftUI

// Colors/materials for the drawn chassis derived from FrameFinish.

public struct FrameThemeColors {
    public let outerBorder: Color
    public let innerBezel: Color
    public let metalGradient: Gradient
}

public enum FrameTheme {
    /// Returns border, bezel, and metal-gradient colors for the given chassis finish.
    public static func colors(for finish: FrameFinish) -> FrameThemeColors {
        palette(for: finish).themeColors
    }

    private static func palette(for finish: FrameFinish) -> ThemePalette {
        switch finish {
        case .naturalTitanium: naturalTitanium
        case .blackTitanium: blackTitanium
        case .whiteTitanium: whiteTitanium
        case .desertTitanium: desertTitanium
        case .midnight: midnight
        case .starlight: starlight
        case .spaceGray: spaceGray
        case .silver: silver
        case .gold: gold
        case .deepPurple: deepPurple
        case .blueTitanium: blueTitanium
        case .pacificBlue: pacificBlue
        case .alpineGreen: alpineGreen
        case .productRed: productRed
        case .pink: pink
        case .ultramarine: ultramarine
        }
    }

    private static let naturalTitanium = ThemePalette(
        border: RGB(0.65, 0.63, 0.60),
        bezel: RGB(0.12, 0.12, 0.12),
        light: RGB(0.74, 0.71, 0.66),
        mid: RGB(0.54, 0.51, 0.47),
        highlight: RGB(0.68, 0.65, 0.61)
    )
    private static let blackTitanium = ThemePalette(
        border: RGB(0.14, 0.14, 0.14),
        bezel: RGB(0.05, 0.05, 0.05),
        light: RGB(0.20, 0.20, 0.20),
        mid: RGB(0.07, 0.07, 0.07),
        highlight: RGB(0.16, 0.16, 0.16)
    )
    private static let whiteTitanium = ThemePalette(
        border: RGB(0.90, 0.90, 0.91),
        bezel: RGB(0.10, 0.10, 0.10),
        light: RGB(0.98, 0.98, 0.99),
        mid: RGB(0.84, 0.84, 0.86),
        highlight: RGB(0.93, 0.93, 0.94)
    )
    private static let desertTitanium = ThemePalette(
        border: RGB(0.80, 0.66, 0.54),
        bezel: RGB(0.12, 0.09, 0.07),
        light: RGB(0.90, 0.76, 0.64),
        mid: RGB(0.70, 0.54, 0.42),
        highlight: RGB(0.84, 0.68, 0.56)
    )
    private static let midnight = ThemePalette(
        border: RGB(0.12, 0.16, 0.26),
        bezel: RGB(0.04, 0.05, 0.10),
        light: RGB(0.18, 0.24, 0.36),
        mid: RGB(0.06, 0.08, 0.16),
        highlight: RGB(0.14, 0.18, 0.28)
    )
    private static let starlight = ThemePalette(
        border: RGB(0.90, 0.86, 0.76),
        bezel: RGB(0.12, 0.10, 0.08),
        light: RGB(0.97, 0.93, 0.84),
        mid: RGB(0.82, 0.74, 0.60),
        highlight: RGB(0.92, 0.86, 0.74)
    )
    private static let spaceGray = ThemePalette(
        border: RGB(0.40, 0.41, 0.44),
        bezel: RGB(0.10, 0.10, 0.11),
        light: RGB(0.52, 0.53, 0.56),
        mid: RGB(0.34, 0.35, 0.38),
        highlight: RGB(0.46, 0.47, 0.50)
    )
    private static let silver = ThemePalette(
        border: RGB(0.76, 0.79, 0.84),
        bezel: RGB(0.12, 0.12, 0.13),
        light: RGB(0.88, 0.91, 0.95),
        mid: RGB(0.66, 0.70, 0.76),
        highlight: RGB(0.80, 0.84, 0.88)
    )
    private static let gold = ThemePalette(
        border: RGB(0.82, 0.70, 0.38),
        bezel: RGB(0.12, 0.10, 0.06),
        light: RGB(0.94, 0.82, 0.46),
        mid: RGB(0.70, 0.54, 0.22),
        highlight: RGB(0.86, 0.72, 0.36)
    )
    private static let deepPurple = ThemePalette(
        border: RGB(0.42, 0.32, 0.54),
        bezel: RGB(0.08, 0.06, 0.12),
        light: RGB(0.54, 0.40, 0.68),
        mid: RGB(0.32, 0.22, 0.44),
        highlight: RGB(0.48, 0.34, 0.60)
    )
    private static let blueTitanium = ThemePalette(
        border: RGB(0.42, 0.50, 0.60),
        bezel: RGB(0.08, 0.10, 0.14),
        light: RGB(0.54, 0.62, 0.72),
        mid: RGB(0.32, 0.40, 0.50),
        highlight: RGB(0.46, 0.54, 0.64)
    )
    private static let pacificBlue = ThemePalette(
        border: RGB(0.16, 0.40, 0.50),
        bezel: RGB(0.04, 0.10, 0.14),
        light: RGB(0.22, 0.52, 0.62),
        mid: RGB(0.08, 0.28, 0.38),
        highlight: RGB(0.16, 0.44, 0.54)
    )
    private static let alpineGreen = ThemePalette(
        border: RGB(0.36, 0.50, 0.42),
        bezel: RGB(0.08, 0.12, 0.10),
        light: RGB(0.48, 0.62, 0.52),
        mid: RGB(0.26, 0.40, 0.32),
        highlight: RGB(0.40, 0.54, 0.44)
    )
    private static let productRed = ThemePalette(
        border: RGB(0.70, 0.16, 0.20),
        bezel: RGB(0.14, 0.04, 0.05),
        light: RGB(0.84, 0.24, 0.28),
        mid: RGB(0.52, 0.08, 0.12),
        highlight: RGB(0.74, 0.16, 0.20)
    )
    private static let pink = ThemePalette(
        border: RGB(0.88, 0.66, 0.72),
        bezel: RGB(0.16, 0.10, 0.12),
        light: RGB(0.96, 0.78, 0.84),
        mid: RGB(0.78, 0.52, 0.60),
        highlight: RGB(0.90, 0.68, 0.74)
    )
    private static let ultramarine = ThemePalette(
        border: RGB(0.28, 0.38, 0.78),
        bezel: RGB(0.06, 0.08, 0.20),
        light: RGB(0.38, 0.50, 0.90),
        mid: RGB(0.16, 0.24, 0.58),
        highlight: RGB(0.30, 0.40, 0.80)
    )
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

private struct ThemePalette {
    let border: RGB
    let bezel: RGB
    let light: RGB
    let mid: RGB
    let highlight: RGB

    var themeColors: FrameThemeColors {
        FrameThemeColors(
            outerBorder: border.color,
            innerBezel: bezel.color,
            metalGradient: Gradient(colors: [light.color, mid.color, highlight.color])
        )
    }
}
