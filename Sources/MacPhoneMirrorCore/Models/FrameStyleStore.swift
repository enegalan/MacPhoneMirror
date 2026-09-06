import Combine
import Foundation

// Observable store so Settings and every mirror window share one frame style.
// Writes through to AppPreferences on change.

@MainActor
public final class FrameStyleStore: ObservableObject {
    public static let shared = FrameStyleStore()

    @Published public var style: FrameRenderStyle {
        didSet {
            guard style != oldValue else { return }
            AppPreferences.frameStyle = style
        }
    }

    /// Loads the persisted style from AppPreferences onto the main actor.
    private init() {
        style = AppPreferences.frameStyle
    }
}
