import Combine
import Foundation

/// Shared, persisted phone-frame appearance used by Settings and mirror windows.
@MainActor
public final class FrameStyleStore: ObservableObject {
    public static let shared = FrameStyleStore()

    @Published public var style: FrameRenderStyle {
        didSet {
            guard style != oldValue else { return }
            AppPreferences.frameStyle = style
        }
    }

    private init() {
        style = AppPreferences.frameStyle
    }
}
