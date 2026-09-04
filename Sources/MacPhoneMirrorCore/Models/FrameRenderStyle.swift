import Foundation

public enum FrameFinish: String, CaseIterable, Identifiable, Codable, Sendable {
    case naturalTitanium = "Natural Titanium"
    case blackTitanium = "Black Titanium"
    case whiteTitanium = "White Titanium"
    case desertTitanium = "Desert Titanium"
    case midnight = "Midnight"
    case starlight = "Starlight"
    case spaceGray = "Space Gray"
    case silver = "Silver"
    case gold = "Gold"
    case deepPurple = "Deep Purple"

    public var id: String {
        rawValue
    }
}

public enum FrameDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case realisticFrame = "Realistic Frame"
    case minimalBezel = "Minimal Bezel"
    case borderless = "Borderless"

    public var id: String {
        rawValue
    }
}

public struct FrameRenderStyle: Codable, Sendable, Equatable {
    public var displayMode: FrameDisplayMode
    public var finish: FrameFinish
    public var showShadow: Bool
    public var showReflection: Bool
    public var showHardwareButtons: Bool
    public var scaleFactor: Double

    public init(
        displayMode: FrameDisplayMode = .realisticFrame,
        finish: FrameFinish = .naturalTitanium,
        showShadow: Bool = true,
        showReflection: Bool = true,
        showHardwareButtons: Bool = true,
        scaleFactor: Double = 1.0
    ) {
        self.displayMode = displayMode
        self.finish = finish
        self.showShadow = showShadow
        self.showReflection = showReflection
        self.showHardwareButtons = showHardwareButtons
        self.scaleFactor = scaleFactor
    }

    public static let standard = FrameRenderStyle()
}
