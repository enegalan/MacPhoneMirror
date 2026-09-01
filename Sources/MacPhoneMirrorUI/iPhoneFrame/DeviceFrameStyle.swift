import MacPhoneMirrorCore
import SwiftUI

public enum FrameTheme {
    public static func colors(for finish: FrameFinish) -> (outerBorder: Color, innerBezel: Color, metalGradient: Gradient) {
        switch finish {
        case .naturalTitanium:
            (
                outerBorder: Color(red: 0.65, green: 0.63, blue: 0.60),
                innerBezel: Color(red: 0.12, green: 0.12, blue: 0.12),
                metalGradient: Gradient(colors: [
                    Color(red: 0.72, green: 0.70, blue: 0.66),
                    Color(red: 0.55, green: 0.53, blue: 0.50),
                    Color(red: 0.68, green: 0.66, blue: 0.63),
                ])
            )
        case .blackTitanium, .midnight, .spaceGray:
            (
                outerBorder: Color(red: 0.22, green: 0.22, blue: 0.24),
                innerBezel: Color(red: 0.08, green: 0.08, blue: 0.08),
                metalGradient: Gradient(colors: [
                    Color(red: 0.28, green: 0.28, blue: 0.30),
                    Color(red: 0.15, green: 0.15, blue: 0.16),
                    Color(red: 0.25, green: 0.25, blue: 0.27),
                ])
            )
        case .whiteTitanium, .silver, .starlight:
            (
                outerBorder: Color(red: 0.88, green: 0.88, blue: 0.90),
                innerBezel: Color(red: 0.10, green: 0.10, blue: 0.10),
                metalGradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.95, blue: 0.97),
                    Color(red: 0.78, green: 0.78, blue: 0.80),
                    Color(red: 0.90, green: 0.90, blue: 0.92),
                ])
            )
        case .desertTitanium, .gold:
            (
                outerBorder: Color(red: 0.78, green: 0.70, blue: 0.62),
                innerBezel: Color(red: 0.10, green: 0.09, blue: 0.08),
                metalGradient: Gradient(colors: [
                    Color(red: 0.84, green: 0.76, blue: 0.68),
                    Color(red: 0.68, green: 0.60, blue: 0.52),
                    Color(red: 0.80, green: 0.72, blue: 0.64),
                ])
            )
        case .deepPurple:
            (
                outerBorder: Color(red: 0.40, green: 0.35, blue: 0.48),
                innerBezel: Color(red: 0.08, green: 0.07, blue: 0.10),
                metalGradient: Gradient(colors: [
                    Color(red: 0.48, green: 0.42, blue: 0.58),
                    Color(red: 0.32, green: 0.28, blue: 0.40),
                    Color(red: 0.45, green: 0.39, blue: 0.54),
                ])
            )
        }
    }
}
